import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("Coach chat second-opinion screen state")
struct CoachChatReviewSupportTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let opus = "anthropic/claude-opus-5"
    private let gemini = "google/gemini-3.1-pro-preview"

    private func agreed(
        draft: Int, reasons: [String] = ["Volume fits"], confidence: String = "high"
    ) -> CoachChatReview {
        CoachChatReview(
            draftIndex: draft, reviewerModelID: opus,
            verdict: .agreed(reasons: reasons, confidence: confidence), finishedAt: now
        )
    }

    private func alternative(
        draft: Int, to index: Int, rationale: String = "Swapped the row in"
    ) -> CoachChatReview {
        CoachChatReview(
            draftIndex: draft, reviewerModelID: opus,
            verdict: .alternative(draftIndex: index, rationale: rationale), finishedAt: now
        )
    }

    private func failed(draft: Int) -> CoachChatReview {
        CoachChatReview(
            draftIndex: draft, reviewerModelID: opus, verdict: .failed(reason: "No connection"),
            finishedAt: now
        )
    }

    // MARK: - Display names

    @Test("The screen's names come from the configuration's id-to-name helpers")
    func displayNames() {
        #expect(CoachChatConfiguration.displayName(forModelID: opus) == "Claude Opus 5")
        #expect(CoachChatConfiguration.displayName(forModelID: gemini) == "Gemini 3.1 Pro")
        #expect(CoachChatConfiguration.shortName(forModelID: opus) == "Opus")
        #expect(CoachChatConfiguration.shortName(forModelID: gemini) == "Gemini")
    }

    // MARK: - Links

    @Test("A drafter's card finds its review; the reviewer's card finds its rationale and origin")
    func links() {
        let reviews = [agreed(draft: 0), alternative(draft: 1, to: 2)]
        #expect(CoachDraftLinks.review(for: 0, in: reviews)?.draftIndex == 0)
        #expect(CoachDraftLinks.review(for: 2, in: reviews) == nil)
        #expect(CoachDraftLinks.rationale(for: 2, in: reviews) == "Swapped the row in")
        #expect(CoachDraftLinks.rationale(for: 1, in: reviews) == nil)
        #expect(CoachDraftLinks.origin(of: 1, in: reviews) == .drafter)
        #expect(CoachDraftLinks.origin(of: 2, in: reviews) == .reviewer)
        #expect(CoachDraftLinks.linkedDraftIndex(for: 1, in: reviews) == 2)
        #expect(CoachDraftLinks.linkedDraftIndex(for: 2, in: reviews) == 1)
        #expect(CoachDraftLinks.linkedDraftIndex(for: 0, in: reviews) == nil)
    }

    @Test("Applying one card of a pair marks the other Not chosen; undo brings both back")
    func linkedDiscard() {
        let applied = CoachDraftLinks.applied(at: 2, linked: 1, states: [:])
        #expect(applied[2] == .applied)
        #expect(applied[1] == .notChosen)
        #expect(applied[1]?.caption == "Not chosen")
        #expect(applied[1]?.isSettled == true)
        let reverted = CoachDraftLinks.reverted(at: 2, linked: 1, states: applied)
        #expect(reverted[2] == .proposed)
        #expect(reverted[1] == .proposed)
    }

    @Test("A card the lifter discarded stays discarded through the pair's apply and undo")
    func linkedDiscardKeepsExplicitDiscard() {
        let applied = CoachDraftLinks.applied(at: 1, linked: 2, states: [2: .discarded])
        #expect(applied[2] == .discarded)
        #expect(CoachDraftLinks.reverted(at: 1, linked: 2, states: applied)[2] == .discarded)
        #expect(CoachDraftLinks.applied(at: 0, linked: nil, states: [:]) == [0: .applied])
    }

    // MARK: - Verdict copy

    @Test("The strip says who agreed, with reasons and confidence; alternatives point below")
    func stripCopy() {
        let strip = CoachReviewCopy.strip(for: agreed(draft: 0, reasons: ["A", "B"], confidence: "medium"))
        #expect(strip == .agreed(title: "Opus agrees", reasons: ["A", "B"], confidence: "Medium confidence"))
        let alternativeStrip = CoachReviewCopy.strip(for: alternative(draft: 0, to: 1))
        #expect(alternativeStrip.title == "Opus proposed a change — see below")
        let failedStrip = CoachReviewCopy.strip(for: failed(draft: 0))
        #expect(failedStrip == .failed(title: "Opus couldn't review this", reason: "No connection"))
    }

    @Test("Origin labels name the drafter on its card and the reviewer on the alternative")
    func originLabels() {
        let reviews = [alternative(draft: 0, to: 1)]
        let drafterLabel = CoachReviewCopy.originLabel(for: 0, in: reviews, drafterModelID: gemini)
        let reviewerLabel = CoachReviewCopy.originLabel(for: 1, in: reviews, drafterModelID: gemini)
        #expect(drafterLabel == "Gemini's proposal")
        #expect(reviewerLabel == "Opus's version")
    }

    @Test("The transcript line carries the full model name and the verdict")
    func transcriptLines() {
        let lines = [agreed(draft: 0), alternative(draft: 0, to: 1), failed(draft: 0)]
            .map(CoachReviewCopy.transcriptLine)
        #expect(lines == [
            "Claude Opus 5 agrees · high confidence",
            "Claude Opus 5 proposed its own version",
            "Claude Opus 5 couldn't review this proposal"
        ])
        #expect(CoachReviewCopy.confidenceLabel("") == "Confidence not stated")
    }

    @Test("A review row never counts as waiting for text")
    func reviewRowIsNotWaiting() {
        let message = CoachChatMessage.review("Claude Opus 5 agrees", index: 0, at: now)
        #expect(message.role == .review)
        #expect(!CoachChatTranscript.isWaitingForText([message]))
    }

    // MARK: - Cost hint

    @Test("The cost hint shows both prices, or the drafter's alone when the reviewer is off")
    func costHint() {
        let cheap = OpenRouterWire.Pricing(prompt: "0.000002", completion: "0.000012")
        let dear = OpenRouterWire.Pricing(prompt: "0.000005", completion: "0.000025")
        let both = CoachChatCostHint.line(
            drafterModelID: gemini, drafterPricing: cheap, reviewerModelID: opus, reviewerPricing: dear
        )
        #expect(both.contains("Gemini 3.1 Pro ($2.00 in · $12.00 out per 1M tokens)"))
        #expect(both.contains("Claude Opus 5 ($5.00 in · $25.00 out per 1M tokens)"))
        let off = CoachChatCostHint.line(
            drafterModelID: gemini, drafterPricing: cheap, reviewerModelID: nil, reviewerPricing: nil
        )
        #expect(off.contains("Gemini 3.1 Pro ($2.00 in"))
        #expect(!off.contains("Claude"))
        let unpriced = CoachChatCostHint.line(
            drafterModelID: gemini, drafterPricing: nil, reviewerModelID: opus, reviewerPricing: nil
        )
        #expect(unpriced.contains("Claude Opus 5"))
        #expect(!unpriced.contains("$"))
    }

    @Test("Picker roles: only the second opinion can be off")
    func pickerRoles() {
        #expect(CoachModelRole.reviewer.canBeOff)
        #expect(!CoachModelRole.coach.canBeOff)
        #expect(CoachModelRole.reviewer.title == "Second opinion")
    }
}
