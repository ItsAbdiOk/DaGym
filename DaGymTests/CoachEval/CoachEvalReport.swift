import Foundation
import GymCore

/// One scenario's scorecard, as the JSON report stores it and the Markdown table reads it.
struct CoachEvalResult: Codable {
    struct WeightRecord: Codable {
        var exercise: String
        var proposedKg: Double
        var bestKg: Double
        var deviationPercent: Double
        var ok: Bool
    }

    struct MuscleRecord: Codable {
        var muscle: String
        var recentWeeklySets: Double
        var proposedWeeklySets: Double
    }

    var id: String
    var title: String
    var prompt: String
    var expectsProposal: Bool
    /// (a) A usable answer: a proposal that validated first time (or, for a question, a clean
    /// reply) with no rejected round-trip and no app-written failure note.
    var proposalOK: Bool
    var proposalNotes: [String] = []
    var draftSummaries: [String] = []
    var reviewerDrafts = 0
    var rejectedProposals = 0
    var failureNotes = 0
    /// (b) Proposed weights against recent bests.
    var weightChecks: [WeightRecord] = []
    var weightScore: Double?
    var worstDeviationPercent: Double?
    /// (c) Weekly sets against the recent week.
    var volumeExpectation: CoachEvalScoring.VolumeExpectation
    var volumeVerdict: CoachEvalScoring.VolumeVerdict
    var volumeScore: Double?
    var recentWeeklySets: Double = 0
    var proposedWeeklySets: Double = 0
    var volumeByMuscle: [MuscleRecord] = []
    /// (d) Keyword heuristic, not a judgement of the reasoning.
    var evidenceScore: Double?
    var evidenceKeywordsHit: [String] = []
    /// House-rule heuristics: `**bold**` or headings despite "no markdown emphasis", and a
    /// reply that asks the lifter something and proposes nothing, instead of proceeding on an
    /// assumption.
    var usesMarkdownEmphasis = false
    var asksInsteadOfProposing = false
    /// (e)
    var toolCalls = 0
    var toolErrors = 0
    var toolNames: [String] = []
    var rounds = 0
    /// (f)
    var seconds: Double = 0
    var promptTokens = 0
    var completionTokens = 0
    var costUSD: Double?
    var reply: String = ""
    var error: String?

    /// Mean of the components that applied, 0…1.
    var overall: Double {
        let parts = [proposalOK ? 1.0 : 0.0, weightScore, volumeScore, evidenceScore].compactMap { $0 }
        return parts.reduce(0, +) / Double(parts.count)
    }

    /// `EVAL <scenario> ok=… weight%=… volume=… rounds=… tools=… secs=… cost=$…` — the line
    /// that shows up in xcodebuild output.
    var summaryLine: String {
        let weight = worstDeviationPercent.map { String(format: "%+.1f", $0) } ?? "n/a"
        let cost = costUSD.map { String(format: "%.4f", $0) } ?? "n/a"
        return "EVAL \(id) ok=\(proposalOK ? 1 : 0) weight%=\(weight) volume=\(volumeVerdict.rawValue) "
            + "rounds=\(rounds) tools=\(toolCalls) secs=\(Int(seconds.rounded())) cost=$\(cost)"
            + (error.map { " error=\($0)" } ?? "")
    }
}

/// The whole run: models, credit before and after, and one result per scenario attempted.
struct CoachEvalReport: Codable {
    var startedAt: Date
    var finishedAt: Date?
    var drafterModelID: String
    var reviewerModelID: String?
    var creditBefore: CoachEvalCredit.Balance?
    var creditAfter: CoachEvalCredit.Balance?
    var creditBeforeUSD: Double? { creditBefore?.remainingUSD }
    var creditAfterUSD: Double? { creditAfter?.remainingUSD }
    var abortedForCredit = false
    var results: [CoachEvalResult] = []

    var totalCostUSD: Double { results.compactMap(\.costUSD).reduce(0, +) }

    // MARK: - Writing

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Writes `coach-eval.json` and `coach-eval.md` into `directory`, creating it.
    func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(self).write(to: directory.appendingPathComponent("coach-eval.json"))
        try Data(markdown.utf8).write(to: directory.appendingPathComponent("coach-eval.md"))
    }

    private static func money(_ value: Double?) -> String {
        value.map { String(format: "$%.2f", $0) } ?? "n/a"
    }

    private static func fraction(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "–"
    }

    var markdown: String {
        var lines = [
            "# Coach chat eval", "",
            "- Drafter: `\(drafterModelID)`; reviewer: `\(reviewerModelID ?? "off")`",
            "- Credit before: \(creditBefore?.line ?? "n/a")",
            "- Credit after: \(creditAfter?.line ?? "n/a")",
            "- Run cost as OpenRouter reported it per reply: \(Self.money(totalCostUSD))"
                + (abortedForCredit ? " (aborted: credit low)" : ""),
            "- Scores: ok = proposal validated first time (or a clean answer); weight = fraction of "
                + "proposed weights within the band of the recent best (worst deviation in brackets); "
                + "volume = weekly sets vs the last week against the scenario's expectation; evidence = "
                + "keyword heuristic only.",
            "",
            "| Scenario | ok | weight | volume | evidence | rounds | tools | secs | cost | overall |",
            "|---|---|---|---|---|---|---|---|---|---|"
        ]
        for result in results {
            let worst = result.worstDeviationPercent.map { String(format: " (%+.0f%%)", $0) } ?? ""
            let okay = result.proposalOK ? 1 : 0
            lines.append(
                "| \(result.id) | \(okay) | \(Self.fraction(result.weightScore))\(worst) "
                    + "| \(result.volumeVerdict.rawValue)/\(result.volumeExpectation.rawValue) "
                    + "| \(Self.fraction(result.evidenceScore)) | \(result.rounds) | \(result.toolCalls) "
                    + "| \(Int(result.seconds.rounded())) | \(Self.money(result.costUSD)) "
                    + "| \(Self.fraction(result.overall)) |"
            )
        }
        for result in results {
            lines += ["", "## \(result.id) — \(result.title)", "", "Prompt: \(result.prompt)", ""]
            if let error = result.error { lines.append("Error: \(error)") }
            lines += result.proposalNotes.map { "- \($0)" }
            lines += result.draftSummaries.map { "- Draft: \($0)" }
            if !result.weightChecks.isEmpty {
                lines.append("- Weights: " + result.weightChecks.map {
                    String(format: "%@ %.1f vs best %.1f (%+.0f%%)", $0.exercise, $0.proposedKg, $0.bestKg,
                           $0.deviationPercent)
                }.joined(separator: "; "))
            }
            lines.append(String(
                format: "- Volume: %.0f proposed vs %.0f recent weekly sets", result.proposedWeeklySets,
                result.recentWeeklySets
            ))
            lines.append("- Tools: " + result.toolNames.joined(separator: ", "))
            lines.append("- Evidence hit: " + result.evidenceKeywordsHit.joined(separator: ", "))
            lines.append("- Markdown emphasis: \(result.usesMarkdownEmphasis); asks instead of proposing: "
                + "\(result.asksInsteadOfProposing)")
            lines += ["", "> " + result.reply.replacingOccurrences(of: "\n", with: "\n> ")]
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
