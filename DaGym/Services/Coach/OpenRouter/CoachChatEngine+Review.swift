import Foundation
import GymCore

/// The second opinion. After a drafter turn ends with new proposals, each one goes to the
/// reviewer model in its own request: the same system prompt plus `reviewerAddendum`, one user
/// message carrying the lifter's request, the drafter's final words and the proposal as JSON,
/// and the reviewer's catalogue (reads, proposals, `agree_with_proposal`). Reads run against
/// the store for real; a `propose_*` result becomes a `.reviewer` draft; `agree_with_proposal`
/// is answered by the engine itself. Every step lands in the transcript under the review's
/// index, and the outcome is a `CoachChatReview`. A reviewer that fails leaves the drafter's
/// card untouched.
extension CoachChatEngine {
    static let maxReviewRounds = 6

    /// Reviews every draft the drafter added this turn, in order. Stops at the first
    /// cancellation; the review under way is recorded as failed so the card says why.
    func reviewNewDrafts(from draftBase: Int, request: String) async {
        let drafterText = messages.last { $0.role == .assistant && $0.isNote != true }?.text ?? ""
        for index in draftBase..<drafts.count where origin(ofDraft: index) == .drafter {
            if Task.isCancelled { return }
            await review(draftIndex: index, request: request, drafterText: drafterText)
        }
    }

    /// One review: request → tool rounds → verdict. `request` is the lifter's message that led
    /// to the draft and `drafterText` the drafter's closing words, both quoted to the reviewer.
    func review(draftIndex: Int, request: String, drafterText: String) async {
        guard let session = ReviewSession(configuration: configuration, reviewIndex: reviews.count) else {
            return
        }
        var chip = CoachChatMessage.tool("review", at: clock())
        chip.text = "Second opinion · \(session.reviewerName)"
        chip.reviewIndex = session.reviewIndex
        appendMessage(chip)

        let verdict: CoachChatReview.Verdict
        if let prompt = try? Self.reviewPrompt(
            request: request, drafterText: drafterText, drafterName: session.drafterName,
            draft: drafts[draftIndex]
        ) {
            verdict = await runReview(session, prompt: prompt).verdict
        } else {
            verdict = .failed(reason: "The proposal couldn't be encoded for review.")
        }
        finish(verdict, draftIndex: draftIndex, session: session)
    }

    /// The reviewer's own agent loop, on its own wire transcript. Ends at the first verdict, a
    /// text-only reply, a failure, a cancellation or the round cap.
    private func runReview(_ session: ReviewSession, prompt: String) async -> ReviewOutcome {
        let system = systemPrompt + CoachChatPrompt.reviewerAddendum(drafterName: session.drafterName)
        var wire: [OpenRouterWire.Message] = [.system(system), .user(prompt)]
        var outcome = ReviewOutcome()
        for round in 0..<Self.maxReviewRounds {
            let request = OpenRouterWire.ChatRequest(
                model: session.reviewerModelID, messages: wire,
                tools: reviewerTools.isEmpty ? nil : reviewerTools, maxTokens: configuration.maxTokens
            )
            Self.trace("review \(session.reviewIndex) round \(round): \(request.messages.count) messages")
            let reply: Reply
            do {
                reply = try await consume(request, reviewIndex: session.reviewIndex)
            } catch {
                outcome.note(error)
                return outcome
            }
            wire.append(.assistant(
                reply.text.isEmpty ? nil : reply.text, toolCalls: reply.calls.isEmpty ? nil : reply.calls
            ))
            if !reply.text.isEmpty { outcome.lastText = reply.text }
            if reply.calls.isEmpty { return outcome }
            for call in reply.calls {
                if Task.isCancelled {
                    outcome.stopped = true
                    return outcome
                }
                let content = await handle(call, session: session, outcome: &outcome)
                wire.append(.tool(callID: call.id, content: content))
            }
            if outcome.hasVerdict { return outcome }
        }
        return outcome
    }

    /// One reviewer tool call. `agree_with_proposal` never reaches the executor: the engine
    /// validates the reasons and records them; anything else runs like the drafter's calls,
    /// with the reviewer's name on the chip and its drafts marked `.reviewer`.
    private func handle(
        _ call: OpenRouterWire.ToolCall, session: ReviewSession, outcome: inout ReviewOutcome
    ) async -> String {
        guard call.function.name == CoachChatToolName.agreeWithProposal.rawValue else {
            let draftsBefore = drafts.count
            let content = await execute(
                call, origin: .reviewer, reviewIndex: session.reviewIndex, chipPrefix: session.shortName
            )
            if drafts.count > draftsBefore { outcome.alternativeIndex = drafts.count - 1 }
            return content
        }
        let chipIndex = messages.count
        var chip = CoachChatMessage.tool(call.function.name, at: clock())
        chip.text = "\(session.shortName) · \(chip.text)"
        chip.reviewIndex = session.reviewIndex
        appendMessage(chip)
        do {
            let data = Data(call.function.arguments.utf8)
            let arguments = try JSONDecoder().decode(CoachChatAgreement.self, from: data)
            outcome.agreement = try arguments.validated().get()
            return #"{"recorded":true}"#
        } catch let rejection as CoachChatDraftRejection {
            markToolError(at: chipIndex)
            return Self.errorJSON(rejection.reasons.joined(separator: "; "))
        } catch {
            markToolError(at: chipIndex)
            return Self.errorJSON(
                "agree_with_proposal needs reasons (1–5 strings) and confidence (high|medium)."
            )
        }
    }

    /// Records the review and writes its closing line: the reasons for an agreement, the
    /// reviewer's own words (already streamed) over its alternative card, or a muted note.
    private func finish(_ verdict: CoachChatReview.Verdict, draftIndex: Int, session: ReviewSession) {
        recordReview(CoachChatReview(
            draftIndex: draftIndex, reviewerModelID: session.reviewerModelID, verdict: verdict,
            finishedAt: clock()
        ))
        let index = session.reviewIndex
        switch verdict {
        case .agreed(let reasons, _):
            let line = "\(session.reviewerName) agrees: " + reasons.joined(separator: " · ")
            appendMessage(.review(line, index: index, at: clock()))
        case .alternative(_, let rationale):
            guard rationale.isEmpty else { return }
            appendMessage(.review("\(session.reviewerName) proposed a change.", index: index, at: clock()))
        case .failed(let reason):
            let line = "\(session.reviewerName) couldn't review this: \(reason)"
            appendMessage(.review(line, index: index, isNote: true, at: clock()))
        }
    }

    /// What the reviewer is asked: the lifter's words, the drafter's words, the proposal.
    static func reviewPrompt(
        request: String, drafterText: String, drafterName: String, draft: CoachChatDraft
    ) throws -> String {
        var parts = ["The lifter asked:\n\(request)"]
        if !drafterText.isEmpty { parts.append("\(drafterName) said:\n\(drafterText)") }
        parts.append("Proposal (JSON):\n\(try draft.proposalJSON())")
        return parts.joined(separator: "\n\n")
    }

    /// The names one review runs under; nil when the second opinion is off.
    struct ReviewSession {
        var reviewIndex: Int
        var reviewerModelID: String
        var reviewerName: String
        var shortName: String
        var drafterName: String

        init?(configuration: CoachChatConfiguration, reviewIndex: Int) {
            guard let id = configuration.reviewerModelID, let name = configuration.reviewerDisplayName,
                  let short = configuration.reviewerShortName
            else { return nil }
            self.reviewIndex = reviewIndex
            reviewerModelID = id
            reviewerName = name
            shortName = short
            drafterName = configuration.drafterDisplayName
        }
    }

    /// What one review has gathered so far, resolved into a verdict at the end. Main-actor
    /// like the engine, so `note` can reach its logger.
    @MainActor
    struct ReviewOutcome {
        var agreement: CoachChatAgreement?
        var alternativeIndex: Int?
        var lastText = ""
        var failure: String?
        var stopped = false

        var hasVerdict: Bool { agreement != nil || alternativeIndex != nil }

        /// A stream that threw: a stop, or a transport failure worth a line in the transcript.
        mutating func note(_ error: Error) {
            if error is CancellationError {
                stopped = true
                return
            }
            let typed = error as? OpenRouterError ?? .network(error)
            CoachChatEngine.logger.error("Review failed: \(typed.logDescription, privacy: .public)")
            failure = CoachChatEngine.failureLine(for: typed)
        }

        /// An alternative wins over an agreement when the reviewer did both: the lifter can
        /// still pick the original, and a second card is worth more than a tick.
        var verdict: CoachChatReview.Verdict {
            if let alternativeIndex { return .alternative(draftIndex: alternativeIndex, rationale: lastText) }
            if let agreement {
                return .agreed(reasons: agreement.reasons, confidence: agreement.confidence.rawValue)
            }
            if stopped { return .failed(reason: "Stopped before a verdict.") }
            if let failure { return .failed(reason: failure) }
            return .failed(reason: "It gave no verdict.")
        }
    }
}
