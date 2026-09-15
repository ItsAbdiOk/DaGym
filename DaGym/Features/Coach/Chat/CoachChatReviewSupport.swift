import Foundation
import GymCore

/// The second-opinion half of the chat screen's pure state: which card a review belongs to,
/// what its strip and transcript line say, and how the two linked cards settle when one is
/// applied. Model names come from `CoachChatConfiguration.displayName/shortName(forModelID:)`.
/// No SwiftUI, so `CoachChatReviewSupportTests` covers all of it. The engine owns `reviews`;
/// this only reads them.
///
/// How the cards pair up. The drafter's card at `draftIndex` may have one review; an
/// `.alternative` review adds a second card at its own index, and Apply on either settles both.
enum CoachDraftLinks {
    /// The review of the drafter's card at `index`, if the reviewer has finished with it.
    static func review(for index: Int, in reviews: [CoachChatReview]) -> CoachChatReview? {
        reviews.first { $0.draftIndex == index }
    }

    /// The review that produced the reviewer's card at `index`.
    static func alternativeReview(for index: Int, in reviews: [CoachChatReview]) -> CoachChatReview? {
        reviews.first {
            if case .alternative(let alternativeIndex, _) = $0.verdict { return alternativeIndex == index }
            return false
        }
    }

    /// The rationale shown above the reviewer's card; nil for a drafter's card.
    static func rationale(for index: Int, in reviews: [CoachChatReview]) -> String? {
        guard case .alternative(_, let rationale)? = alternativeReview(for: index, in: reviews)?.verdict
        else { return nil }
        return rationale
    }

    /// Whether the card at `index` was proposed by the drafter or by the reviewer.
    static func origin(of index: Int, in reviews: [CoachChatReview]) -> CoachChatDraftOrigin {
        alternativeReview(for: index, in: reviews) == nil ? .drafter : .reviewer
    }

    /// The other card of the pair, in either direction; nil when the card stands alone.
    static func linkedDraftIndex(for index: Int, in reviews: [CoachChatReview]) -> Int? {
        if let review = alternativeReview(for: index, in: reviews) { return review.draftIndex }
        if case .alternative(let alternativeIndex, _)? = review(for: index, in: reviews)?.verdict {
            return alternativeIndex
        }
        return nil
    }

    /// The card states after Apply on `index`: it is applied and its linked card, if still
    /// proposed, is "Not chosen". Already-settled cards are left alone.
    static func applied(
        at index: Int, linked: Int?, states: [Int: CoachDraftCardState]
    ) -> [Int: CoachDraftCardState] {
        var next = states
        next[index] = .applied
        if let linked, (next[linked] ?? .proposed) == .proposed { next[linked] = .notChosen }
        return next
    }

    /// Undo of that Apply: both cards return to proposed, but a card the lifter had discarded
    /// on purpose stays discarded.
    static func reverted(
        at index: Int, linked: Int?, states: [Int: CoachDraftCardState]
    ) -> [Int: CoachDraftCardState] {
        var next = states
        next[index] = .proposed
        if let linked, next[linked] == .notChosen { next[linked] = .proposed }
        return next
    }
}

/// The words on a card's review strip and on the transcript's review line.
enum CoachReviewCopy {
    /// What the strip on the drafter's card draws.
    enum Strip: Equatable, Sendable {
        case agreed(title: String, reasons: [String], confidence: String)
        case alternative(title: String)
        case failed(title: String, reason: String)

        var title: String {
            switch self {
            case .agreed(let title, _, _), .alternative(let title), .failed(let title, _): title
            }
        }
    }

    static func strip(for review: CoachChatReview) -> Strip {
        let name = CoachChatConfiguration.shortName(forModelID: review.reviewerModelID)
        switch review.verdict {
        case .agreed(let reasons, let confidence):
            return .agreed(title: "\(name) agrees", reasons: reasons, confidence: confidenceLabel(confidence))
        case .alternative:
            return .alternative(title: "\(name) proposed a change — see below")
        case .failed(let reason):
            return .failed(title: "\(name) couldn't review this", reason: reason)
        }
    }

    /// "Gemini's proposal" on the drafter's card, "Opus's version" on the reviewer's.
    static func originLabel(
        for index: Int, in reviews: [CoachChatReview], drafterModelID: String
    ) -> String {
        if let review = CoachDraftLinks.alternativeReview(for: index, in: reviews) {
            return "\(CoachChatConfiguration.shortName(forModelID: review.reviewerModelID))'s version"
        }
        return "\(CoachChatConfiguration.shortName(forModelID: drafterModelID))'s proposal"
    }

    /// The transcript's compact line: full model name and the verdict in a few words.
    static func transcriptLine(for review: CoachChatReview) -> String {
        let name = CoachChatConfiguration.displayName(forModelID: review.reviewerModelID)
        switch review.verdict {
        case .agreed(_, let confidence):
            return "\(name) agrees · \(confidenceLabel(confidence).lowercased())"
        case .alternative:
            return "\(name) proposed its own version"
        case .failed:
            return "\(name) couldn't review this proposal"
        }
    }

    static func confidenceLabel(_ confidence: String) -> String {
        switch confidence.lowercased() {
        case "high": "High confidence"
        case "medium": "Medium confidence"
        case "low": "Low confidence"
        default: confidence.isEmpty ? "Confidence not stated" : confidence
        }
    }
}

/// Settings › Coach's one-line cost hint: both models' prices, or the drafter's alone when the
/// second opinion is off. Prices come from the same GET /models the picker uses.
enum CoachChatCostHint {
    static func line(
        drafterModelID: String, drafterPricing: OpenRouterWire.Pricing?,
        reviewerModelID: String?, reviewerPricing: OpenRouterWire.Pricing?
    ) -> String {
        let drafter = CoachChatConfiguration.displayName(forModelID: drafterModelID)
        let drafterPrice = CoachModelPricingText.line(for: drafterPricing)
        guard let reviewerModelID else {
            let price = drafterPrice.map { " (\($0))" } ?? ""
            return "Each question is billed to \(drafter)\(price). Add a second opinion and every proposal "
                + "is also sent to that model."
        }
        let reviewer = CoachChatConfiguration.displayName(forModelID: reviewerModelID)
        let reviewerPrice = CoachModelPricingText.line(for: reviewerPricing)
        if let drafterPrice, let reviewerPrice {
            return "Each question is billed to \(drafter) (\(drafterPrice)); each proposal is also billed to "
                + "\(reviewer) (\(reviewerPrice))."
        }
        return "Each question is billed to \(drafter); each proposal is also billed to \(reviewer). "
            + "Prices are in the model picker."
    }
}
