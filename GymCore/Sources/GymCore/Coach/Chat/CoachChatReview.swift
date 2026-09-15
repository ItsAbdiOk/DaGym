import Foundation

/// The arguments of `agree_with_proposal`: why the reviewer thinks the drafter's proposal
/// stands. Decoded from the tool call, then `validate`d so an empty or padded list never
/// reaches the card.
public struct CoachChatAgreement: Codable, Hashable, Sendable {
    public enum Confidence: String, CaseIterable, Codable, Hashable, Sendable {
        case high, medium
    }

    public static let reasonsRange = 1...5
    public static let maxReasonLength = 160

    public var reasons: [String]
    public var confidence: Confidence

    public init(reasons: [String], confidence: Confidence) {
        self.reasons = reasons
        self.confidence = confidence
    }

    /// Trimmed, blank lines dropped, each reason cut to `maxReasonLength`, the list cut to the
    /// range's top; a failure only when nothing usable is left.
    public func validated() -> Result<CoachChatAgreement, CoachChatDraftRejection> {
        let lines = reasons
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(Self.maxReasonLength)) }
        guard lines.count >= Self.reasonsRange.lowerBound else {
            return .failure(CoachChatDraftRejection(reasons: ["Give at least one reason."]))
        }
        return .success(CoachChatAgreement(
            reasons: Array(lines.prefix(Self.reasonsRange.upperBound)), confidence: confidence
        ))
    }
}

/// What the second-opinion model made of one draft. `draftIndex` is the drafter's proposal in
/// the thread's `drafts`; an `.alternative` points at the reviewer's own draft in the same list.
public struct CoachChatReview: Codable, Hashable, Sendable {
    public enum Verdict: Codable, Hashable, Sendable {
        /// The proposal stands; `confidence` is a `CoachChatAgreement.Confidence` raw value.
        case agreed(reasons: [String], confidence: String)
        /// The reviewer put up its own draft; `rationale` is its own words on what changed and why.
        case alternative(draftIndex: Int, rationale: String)
        /// The review never reached a verdict (transport, tool or round-cap failure).
        case failed(reason: String)
    }

    public var draftIndex: Int
    public var reviewerModelID: String
    public var verdict: Verdict
    public var finishedAt: Date

    public init(draftIndex: Int, reviewerModelID: String, verdict: Verdict, finishedAt: Date) {
        self.draftIndex = draftIndex
        self.reviewerModelID = reviewerModelID
        self.verdict = verdict
        self.finishedAt = finishedAt
    }

    /// The reviewer's own draft, when it proposed one.
    public var alternativeDraftIndex: Int? {
        if case .alternative(let index, _) = verdict { return index }
        return nil
    }
}

extension CoachChatDraft {
    /// The `propose_*` tool whose arguments this draft is.
    public var toolName: CoachChatToolName {
        switch self {
        case .routine: .proposeRoutine
        case .program: .proposeProgram
        case .schedule: .proposeSchedule
        case .deload: .proposeDeload
        case .swap: .proposeSwap
        }
    }

    /// The draft as the reviewer reads it: `{"tool": "propose_routine", "arguments": {…}}` with
    /// the proposal in the tool schema's own snake_case keys, so the reviewer can re-propose by
    /// editing what it sees.
    public func proposalJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let arguments: Data
        switch self {
        case .routine(let proposal): arguments = try encoder.encode(proposal)
        case .program(let proposal): arguments = try encoder.encode(proposal)
        case .schedule(let proposal): arguments = try encoder.encode(proposal)
        case .deload(let proposal): arguments = try encoder.encode(proposal)
        case .swap(let proposal): arguments = try encoder.encode(proposal)
        }
        guard let body = String(bytes: arguments, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                self, EncodingError.Context(codingPath: [], debugDescription: "not UTF-8")
            )
        }
        return #"{"tool":"\#(toolName.rawValue)","arguments":\#(body)}"#
    }
}
