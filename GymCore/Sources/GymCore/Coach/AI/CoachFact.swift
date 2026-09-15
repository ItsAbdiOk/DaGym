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
}
