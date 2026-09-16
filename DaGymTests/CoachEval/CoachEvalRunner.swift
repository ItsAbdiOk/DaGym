import Foundation
import GymCore
import os

@testable import DaGym

/// Counts chat requests on their way to OpenRouter so the report can say how many rounds a
/// turn took; everything else is the real `URLSessionTransport`.
final class CoachEvalCountingTransport: OpenRouterTransport {
    private let inner = URLSessionTransport()
    private let count = OSAllocatedUnfairLock(initialState: 0)

    var requests: Int { count.withLock { $0 } }

    func lines(for request: URLRequest) async throws -> OpenRouterTransportReply {
        count.withLock { $0 += 1 }
        return try await inner.lines(for: request)
    }
}

/// `GET /auth/key`: what the key has left. Numbers only; the key never leaves the header.
enum CoachEvalCredit {
    static let url = URL(string: "https://openrouter.ai/api/v1/auth/key")

    /// The key's balance as OpenRouter reports it. `remainingUSD` is `limit_remaining` (or
    /// `limit − usage`); nil for an unlimited key.
    struct Balance: Codable {
        var limitUSD: Double?
        var usageUSD: Double?
        var remainingUSD: Double?
        var isFreeTier: Bool?

        var line: String {
            func money(_ value: Double?) -> String { value.map { String(format: "$%.4f", $0) } ?? "n/a" }
            return "remaining \(money(remainingUSD)) (limit \(money(limitUSD)), usage \(money(usageUSD)), "
                + "free tier \(isFreeTier.map(String.init) ?? "n/a"))"
        }
    }

    /// nil when the lookup failed.
    static func balance(key: String) async -> Balance? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any] else { return nil }
        let limit = payload["limit"] as? Double
        let usage = payload["usage"] as? Double
        let remaining = (payload["limit_remaining"] as? Double) ?? limit.map { $0 - (usage ?? 0) }
        return Balance(
            limitUSD: limit, usageUSD: usage, remainingUSD: remaining,
            isFreeTier: payload["is_free_tier"] as? Bool
        )
    }
}

/// Runs one scenario through the real engine, executor and OpenRouter, then scores it.
@MainActor
enum CoachEvalRunner {
    /// The key: the environment first, then what the app on this simulator keeps in its
    /// Keychain. Never printed.
    nonisolated static func apiKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["DAGYM_COACH_EVAL_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return CoachChatSettings.apiKey()
    }

    nonisolated static var reviewerEnabled: Bool {
        ProcessInfo.processInfo.environment["DAGYM_COACH_EVAL_REVIEW"] == "1"
    }

    static func run(
        _ scenario: CoachEvalScenario, key: String, review: Bool, deadline: Duration
    ) async throws -> CoachEvalResult {
        let builder = try CoachEvalStoreBuilder()
        try scenario.seed(builder)
        builder.finish()
        let made = try makeEngine(for: scenario, builder: builder, key: key, review: review)
        let engine = made.engine
        var result = CoachEvalResult(
            id: scenario.id, title: scenario.title, prompt: scenario.prompt,
            expectsProposal: scenario.expectsProposal, proposalOK: false,
            volumeExpectation: scenario.volumeExpectation, volumeVerdict: .none
        )

        let started = Date()
        let watchdog = Task {
            try? await Task.sleep(for: deadline)
            engine.cancel()
        }
        await engine.send(scenario.prompt)
        watchdog.cancel()
        result.seconds = Date().timeIntervalSince(started)
        if result.seconds >= deadline.seconds - 1 { result.error = "deadline (\(Int(deadline.seconds)) s)" }
        if let error = engine.lastError { result.error = error.logDescription }

        score(&result, engine: made, scenario: scenario, builder: builder, rounds: made.client.requests)
        return result
    }

    // MARK: - Engine

    private struct Engine {
        var engine: CoachChatEngine
        var client: CoachEvalCountingTransport
    }

    private static func makeEngine(
        for scenario: CoachEvalScenario, builder: CoachEvalStoreBuilder, key: String, review: Bool
    ) throws -> Engine {
        let transport = CoachEvalCountingTransport()
        let client = OpenRouterClient(apiKey: { key }, transport: transport)
        let executor = StoreCoachChatToolExecutor(
            store: builder.store, unit: .kg, weeklyGoal: scenario.weeklyGoal, calendar: builder.calendar,
            now: { builder.now }
        )
        var facts = builder.store.lifterProfileFacts(
            unit: .kg, weeklyGoal: scenario.weeklyGoal, trainingGoal: scenario.goal, now: builder.now,
            calendar: builder.calendar
        )
        facts.experience = scenario.experience
        var configuration = CoachChatConfiguration(consentGiven: true)
        configuration.reviewerModelID = review ? CoachChatConfiguration.defaultReviewerModelID : nil
        let engine = CoachChatEngine(
            client: client, executor: executor, configuration: configuration,
            systemPrompt: CoachChatPrompt.system(
                profile: facts, now: builder.now, calendar: builder.calendar
            ),
            tools: try OpenRouterWire.toolDefinitions(), clock: { builder.now }
        )
        return Engine(engine: engine, client: transport)
    }

    // MARK: - Scoring

    private static func score(
        _ result: inout CoachEvalResult, engine: Engine, scenario: CoachEvalScenario,
        builder: CoachEvalStoreBuilder, rounds: Int
    ) {
        let engine = engine.engine
        let tools = engine.messages.filter { $0.role == .tool }
        result.toolCalls = tools.count
        result.toolErrors = tools.filter(\.isToolError).count
        result.toolNames = tools.map { ($0.toolName ?? "?") + ($0.isToolError ? "!" : "") }
        result.rejectedProposals = tools
            .filter { $0.isToolError && ($0.toolName ?? "").hasPrefix("propose_") }.count
        result.failureNotes = engine.messages.filter { $0.role == .assistant && $0.isNote == true }.count
        result.rounds = rounds
        result.promptTokens = engine.usage.promptTokens
        result.completionTokens = engine.usage.completionTokens
        result.costUSD = engine.usage.costUSD
        result.reply = engine.messages.filter { $0.role == .assistant && $0.isNote != true }
            .map(\.text).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let drafterDrafts = engine.drafts.indices.filter { engine.origin(ofDraft: $0) == .drafter }
            .map { engine.drafts[$0] }
        result.reviewerDrafts = engine.drafts.count - drafterDrafts.count
        result.draftSummaries = engine.drafts.map(\.summary)
        scoreProposal(&result, drafts: drafterDrafts, scenario: scenario)
        scoreWeights(&result, drafts: drafterDrafts, scenario: scenario, builder: builder)
        scoreVolume(&result, drafts: drafterDrafts, scenario: scenario, builder: builder)
        scoreEvidence(&result, scenario: scenario)
    }

    /// (a) One clean proposal (or, for a question, a clean reply).
    private static func scoreProposal(
        _ result: inout CoachEvalResult, drafts: [CoachChatDraft], scenario: CoachEvalScenario
    ) {
        var notes: [String] = []
        if result.error != nil { notes.append("turn failed: \(result.error ?? "")") }
        if result.rejectedProposals > 0 {
            notes.append("\(result.rejectedProposals) proposal(s) rejected by validation before one passed")
        }
        if result.failureNotes > 0 { notes.append("\(result.failureNotes) app-written failure note(s)") }
        if scenario.expectsProposal, drafts.isEmpty { notes.append("no proposal card was produced") }
        if !scenario.expectsProposal, !drafts.isEmpty {
            notes.append("proposed although the request was a question (not penalised)")
        }
        if result.reply.isEmpty { notes.append("no reply text") }
        result.proposalNotes = notes
        let clean = result.error == nil && result.rejectedProposals == 0 && result.failureNotes == 0
        result.proposalOK = clean && (scenario.expectsProposal ? !drafts.isEmpty : !result.reply.isEmpty)
    }

    /// The exercises a proposal programs, with weekly frequency, resolved through the library.
    static func proposedExercises(
        drafts: [CoachChatDraft], scenario: CoachEvalScenario, builder: CoachEvalStoreBuilder
    ) -> [CoachEvalScoring.ProposedExercise] {
        let library = Dictionary(
            builder.store.substitutionCandidates().map { ($0.id, $0.primary) },
            uniquingKeysWith: { first, _ in first }
        )
        let routineDrafts = drafts.filter { if case .routine = $0 { true } else { false } }.count
        func exercises(
            _ routine: RoutineProposal, timesPerWeek: Double
        ) -> [CoachEvalScoring.ProposedExercise] {
            routine.exercises.map { spec in
                let working = spec.sets.filter { $0.kind == .working }
                return CoachEvalScoring.ProposedExercise(
                    exercise: spec.exerciseName ?? "?",
                    primaryMuscles: spec.exerciseID.flatMap { library[$0] } ?? [],
                    workingSets: working.count, weightKg: working.compactMap(\.targetWeightKg).max(),
                    timesPerWeek: timesPerWeek
                )
            }
        }
        return drafts.flatMap { draft -> [CoachEvalScoring.ProposedExercise] in
            switch draft {
            case .routine(let routine):
                exercises(
                    routine, timesPerWeek: max(1, scenario.sessionsPerWeek / Double(max(1, routineDrafts)))
                )
            case .program(let program):
                program.routines.flatMap {
                    exercises(
                        $0, timesPerWeek: Double(program.daysPerWeek) / Double(max(1, program.routines.count))
                    )
                }
            case .deload(let deload):
                // A deload proposes a weight, not sets: the working weight the app would cut
                // from, less the percentage. No sets, so it never counts towards volume.
                deloadWeight(deload, builder: builder).map { weight in
                    [CoachEvalScoring.ProposedExercise(
                        exercise: deload.exerciseName ?? "?", primaryMuscles: [], workingSets: 0,
                        weightKg: weight
                    )]
                } ?? []
            case .schedule, .swap: []
            }
        }
    }

    private static func deloadWeight(_ deload: DeloadProposal, builder: CoachEvalStoreBuilder) -> Double? {
        guard let id = deload.exerciseID, let base = builder.store.coachChatWorkingWeightKg(exerciseID: id)
        else { return nil }
        return base * (1 - deload.percent / 100)
    }

    /// (b)
    private static func scoreWeights(
        _ result: inout CoachEvalResult, drafts: [CoachChatDraft], scenario: CoachEvalScenario,
        builder: CoachEvalStoreBuilder
    ) {
        let proposed = proposedExercises(drafts: drafts, scenario: scenario, builder: builder)
        let since = builder.now.addingTimeInterval(-scenario.bestsWindowDays * 86_400)
        let bests = CoachEvalScoring.recentBestsKg(history: builder.history, since: since)
        let checks = CoachEvalScoring.weightChecks(proposed: proposed, bestsKg: bests)
        result.weightChecks = checks.map {
            CoachEvalResult.WeightRecord(
                exercise: $0.exercise, proposedKg: $0.proposedKg, bestKg: $0.bestKg,
                deviationPercent: $0.deviationPercent, ok: $0.isAcceptable(in: scenario.weightBand)
            )
        }
        result.weightScore = CoachEvalScoring.weightScore(checks, band: scenario.weightBand)
        result.worstDeviationPercent = CoachEvalScoring.worstDeviationPercent(checks)
    }

    /// (c)
    private static func scoreVolume(
        _ result: inout CoachEvalResult, drafts: [CoachChatDraft], scenario: CoachEvalScenario,
        builder: CoachEvalStoreBuilder
    ) {
        let proposed = CoachEvalScoring.proposedWeeklySets(
            proposedExercises(drafts: drafts, scenario: scenario, builder: builder)
        )
        let recent = CoachEvalScoring.recentWeeklySets(history: builder.history, now: builder.now)
        result.volumeVerdict = CoachEvalScoring.volumeVerdict(recent: recent, proposed: proposed)
        result.volumeScore = CoachEvalScoring.volumeScore(
            result.volumeVerdict, expectation: scenario.volumeExpectation
        )
        result.recentWeeklySets = recent.values.reduce(0, +)
        result.proposedWeeklySets = proposed.values.reduce(0, +)
        result.volumeByMuscle = CoachEvalScoring.volumeChecks(recent: recent, proposed: proposed).map {
            CoachEvalResult.MuscleRecord(
                muscle: $0.muscle.rawValue, recentWeeklySets: $0.recentWeeklySets,
                proposedWeeklySets: $0.proposedWeeklySets
            )
        }
    }

    /// (d)
    private static func scoreEvidence(_ result: inout CoachEvalResult, scenario: CoachEvalScenario) {
        result.evidenceScore = CoachEvalScoring.evidenceScore(
            reply: result.reply, keywordGroups: scenario.evidenceKeywords
        )
        let text = result.reply.lowercased()
        result.evidenceKeywordsHit = scenario.evidenceKeywords
            .compactMap { group in group.first { text.contains($0.lowercased()) } }
        result.usesMarkdownEmphasis = result.reply.contains("**") || result.reply.contains("\n#")
        result.asksInsteadOfProposing = result.reply.contains("?") && result.draftSummaries.isEmpty
    }
}

private extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
