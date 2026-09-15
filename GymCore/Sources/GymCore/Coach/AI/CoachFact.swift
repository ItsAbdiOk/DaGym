import Foundation

/// One pre-summarised statement the on-device coach may reason from, with a stable id the model
/// must cite back (plan.md §6.6: "the deterministic engine does the maths, the model chooses and
/// explains"). Every AI feature hands the model a short list of these — never raw history — and
/// every claim it returns must name the ids it rests on, or the validator drops the claim.
public struct CoachFact: Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }

    /// The compact "id: text" line the prompt carries — one fact per line, no prose around it.
    public var promptLine: String { "\(id): \(text)" }
}

/// One sentence the model wrote, plus the fact ids it says support it. Shared by the debrief
/// (`SessionDebrief`) and the training review (`ReviewProposal`).
public struct CoachClaim: Hashable, Sendable {
    public var text: String
    public var citedFactIDs: [String]

    public init(text: String, citedFactIDs: [String]) {
        self.text = text
        self.citedFactIDs = citedFactIDs
    }

    /// True when the claim is non-empty and every cited id is one of `knownIDs`. A claim that
    /// cites nothing is uncited — the validator treats "no evidence" the same as "made up".
    public func isGrounded(in knownIDs: Set<String>) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !citedFactIDs.isEmpty else { return false }
        return citedFactIDs.allSatisfy { knownIDs.contains($0) }
    }

    /// `isGrounded(in:)` plus the number check the Ask feature applies to a model sentence:
    /// every numeric token in the claim must be a value that appears in `knownText` (the
    /// fact lines and any names the claim may repeat). Citations alone let "Volume was up
    /// 40 %" through against a fact that said +4 % — the model does no maths, so a number the
    /// facts never stated is a number it invented, and the claim is dropped.
    public func isGrounded(in knownIDs: Set<String>, numbersFrom knownText: [String]) -> Bool {
        guard isGrounded(in: knownIDs) else { return false }
        let allowed = knownText.flatMap { CoachAnswerValidator.numbers(in: $0) }
        return CoachAnswerValidator.numbers(in: text).allSatisfy { number in
            allowed.contains { abs($0 - number) < 0.001 }
        }
    }
}
