import Foundation
import GymCore
import Testing

@testable import DaGym

// A scoreboard a human reads from the xcodebuild log, not app code.
// swiftlint:disable no_print_statements

/// Scores the cloud coach against eight scripted lifters — real `CoachChatEngine`, real
/// `StoreCoachChatToolExecutor` over an in-memory store, real OpenRouter — so the prompt can
/// be tuned against numbers. Skipped without a key: `DAGYM_COACH_EVAL_KEY` in the runner's
/// environment (`TEST_RUNNER_DAGYM_COACH_EVAL_KEY=…` to xcodebuild), else — only with
/// `DAGYM_COACH_EVAL=1` — the key the app on this simulator holds in its Keychain.
/// `DAGYM_COACH_EVAL_REVIEW=1` turns the second opinion on; `DAGYM_COACH_EVAL_OUT` is where
/// `coach-eval.json` and `coach-eval.md` land (the temp directory by default). Not part of the
/// gate: it spends real credit and takes minutes.
@MainActor
@Suite("Coach chat eval", .serialized)
struct CoachEvalTests {
    /// Below this the run stops after the current scenario and writes what it has.
    static let minimumCreditUSD = 0.40
    static let perScenarioDeadline: Duration = .seconds(360)

    static var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["DAGYM_COACH_EVAL_OUT"]
        return path.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dagym-coach-eval")
    }

    private static let skipReason: Comment =
        "set DAGYM_COACH_EVAL_KEY, or DAGYM_COACH_EVAL=1 with the simulator's key"

    @Test("every scenario seeds a store with history the tools can read (no key needed)")
    func scenariosSeed() async throws {
        for scenario in CoachEvalScenarios.all {
            let builder = try CoachEvalStoreBuilder()
            try scenario.seed(builder)
            builder.finish()
            #expect(!builder.history.isEmpty, "\(scenario.id) has history")
            let executor = StoreCoachChatToolExecutor(
                store: builder.store, unit: .kg, weeklyGoal: scenario.weeklyGoal, calendar: builder.calendar,
                now: { builder.now }
            )
            let result = try await executor.execute(name: CoachChatToolName.getRecentWorkouts.rawValue,
                                                    argumentsJSON: #"{"limit": 3}"#)
            guard case .json(let json) = result else {
                Issue.record("expected JSON")
                return
            }
            #expect(json.contains("\"workouts\""), "\(scenario.id) recent workouts readable")
            if scenario.id != "returning-3wk" {
                let recent = CoachEvalScoring.recentWeeklySets(history: builder.history, now: builder.now)
                #expect(!recent.isEmpty, "\(scenario.id) trained in the last week")
            }
        }
    }

    @Test(
        "the key's balance can be read (numbers only)",
        .enabled(if: CoachEvalRunner.apiKey() != nil, Self.skipReason)
    )
    func creditLookup() async throws {
        let key = try #require(CoachEvalRunner.apiKey())
        let balance = try #require(await CoachEvalCredit.balance(key: key))
        print("EVAL credit: \(balance.line)")
    }

    @Test(
        "eight lifters through the real coach, scored",
        .enabled(if: CoachEvalRunner.apiKey() != nil, Self.skipReason)
    )
    func liveEval() async throws {
        let key = try #require(CoachEvalRunner.apiKey())
        let review = CoachEvalRunner.reviewerEnabled
        var report = CoachEvalReport(
            startedAt: Date(), drafterModelID: CoachChatConfiguration.defaultModelID,
            reviewerModelID: review ? CoachChatConfiguration.defaultReviewerModelID : nil
        )
        report.creditBefore = await CoachEvalCredit.balance(key: key)
        print("EVAL credit before: \(report.creditBefore?.line ?? "n/a")")

        for scenario in CoachEvalScenarios.all {
            if let credit = report.creditAfterUSD ?? report.creditBeforeUSD, credit < Self.minimumCreditUSD {
                print("EVAL aborting: credit \(Self.money(credit)) < \(Self.money(Self.minimumCreditUSD))")
                report.abortedForCredit = true
                break
            }
            let result: CoachEvalResult
            do {
                result = try await CoachEvalRunner.run(
                    scenario, key: key, review: review, deadline: Self.perScenarioDeadline
                )
            } catch {
                var failed = CoachEvalResult(
                    id: scenario.id, title: scenario.title, prompt: scenario.prompt,
                    expectsProposal: scenario.expectsProposal, proposalOK: false,
                    volumeExpectation: scenario.volumeExpectation, volumeVerdict: .none
                )
                failed.error = "harness: \(error)"
                result = failed
            }
            report.results.append(result)
            print(result.summaryLine)
            report.creditAfter = await CoachEvalCredit.balance(key: key)
            try report.write(to: Self.outputDirectory)
        }

        report.finishedAt = Date()
        report.creditAfter = await CoachEvalCredit.balance(key: key)
        try report.write(to: Self.outputDirectory)
        print("EVAL credit after: \(report.creditAfter?.line ?? "n/a"); reported run cost "
            + "\(Self.money(report.totalCostUSD)); report in \(Self.outputDirectory.path)")
        #expect(!report.results.isEmpty)
        // The scoreboard is the output; a scenario scoring badly is a finding, not a failure.
        // Only a harness-level failure (nothing ran) fails the test.
        #expect(report.results.contains { $0.error?.hasPrefix("harness:") != true })
    }

    private static func money(_ value: Double?) -> String {
        value.map { String(format: "$%.2f", $0) } ?? "n/a"
    }
}

// swiftlint:enable no_print_statements
