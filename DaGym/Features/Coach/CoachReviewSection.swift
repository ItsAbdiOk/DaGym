import GymCore
import SwiftUI

/// "Review my training" on the Coach tab: one tap builds the four-week `TrainingDigest`, asks
/// `CoachLanguageModel.reviewTraining` for up to three changes, and shows each as a
/// `CoachCard` on the same Approve/Dismiss/Undo plumbing as the rule cards. Approving applies
/// the change through `WorkoutStore.applyReviewChange` and the toast's Undo puts it back.
struct CoachReviewSection: View {
    @Binding var undoAction: UndoAction?

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(CoachServices.self) private var coach
    @State private var cards: [CoachCard] = []
    @State private var changes: [String: ReviewChange] = [:]
    @State private var expanded: Set<String> = []
    @State private var isReviewing = false
    @State private var hasReviewed = false
    /// Why the last Approve did nothing, shown under the cards until the next tap.
    @State private var applyFailure: String?
    /// The in-flight review, cancelled when the section leaves the screen.
    @State private var reviewTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack {
                Text("Review").dgLabel()
                Spacer()
                Button(isReviewing ? "Reviewing…" : "Review my training") {
                    reviewTask = Task { await review() }
                }
                    .buttonStyle(.dgControl)
                    .font(DGFont.condensedLabel(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DGSpace.s3)
                    .frame(minHeight: 36)
                    .background(DGColor.aiViolet, in: Capsule())
                    .disabled(isReviewing)
                    .accessibilityIdentifier(A11yID.coachReview)
            }
            if hasReviewed && cards.isEmpty && !isReviewing {
                Text("Nothing to change — the last four weeks look the way your plan says they should.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(cards, id: \.fingerprint) { card in
                CoachCardView(
                    card: card, isExpanded: expanded.contains(card.fingerprint),
                    formatWeight: preferences.formatWeight,
                    onToggle: { toggle(card) }, onApprove: { approve(card) }, onDismiss: { dismiss(card) }
                )
            }
            if let applyFailure {
                Text(applyFailure)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(A11yID.coachApplyFailure)
            }
        }
        .onDisappear { reviewTask?.cancel() }
    }

    private func review() async {
        isReviewing = true
        defer { isReviewing = false }
        let now = Date()
        let digest = store.trainingDigest(now: now, calendar: preferences.trainingCalendar)
        let fromModel: [ReviewProposal]?
        do {
            fromModel = try await coach.model.reviewTraining(digest: digest)
        } catch {
            coachLogger.error("Training review failed, falling back to rules: \(error, privacy: .public)")
            fromModel = nil
        }
        // A cancelled review (the tab was left) must not repaint a view that is gone, nor
        // count as "reviewed" and show "Nothing to change" next time.
        guard !Task.isCancelled else { return }
        hasReviewed = true
        let proposals = ReviewApproval.proposals(fromModel: fromModel, digest: digest)
        let interactions = store.coachInteractions()
        var built: [CoachCard] = []
        var byFingerprint: [String: ReviewChange] = [:]
        for proposal in proposals {
            let card = ReviewCardBuilder.card(for: proposal, digest: digest, store: store, now: now)
            guard !CoachEngine.isSuppressed(card, interactions: interactions, now: now) else { continue }
            built.append(card)
            byFingerprint[card.fingerprint] = proposal.change
        }
        cards = built
        changes = byFingerprint
    }

    private func toggle(_ card: CoachCard) {
        if expanded.contains(card.fingerprint) {
            expanded.remove(card.fingerprint)
        } else {
            expanded.insert(card.fingerprint)
        }
    }

    private func approve(_ card: CoachCard) {
        applyFailure = nil
        switch ReviewApproval.approve(card: card, change: changes[card.fingerprint], store: store) {
        case .applied(let applied, let interactionID):
            undoAction = UndoAction(message: applied.message) {
                store.undoReviewChange(applied)
                store.removeCoachInteraction(id: interactionID)
                cards.append(card)
            }
            cards.removeAll { $0.fingerprint == card.fingerprint }
        case .refused(let reason):
            // The card stays and nothing is recorded: a "yes" that changed nothing would hide
            // the card for its cool-down while the lifter believes the plan moved.
            applyFailure = reason
        }
    }

    private func dismiss(_ card: CoachCard) {
        applyFailure = nil
        let interactionID = store.recordCoachInteraction(
            rule: card.rule, fingerprint: card.fingerprint, outcome: .dismissed
        )
        undoAction = UndoAction(message: "Dismissed \"\(card.title)\"") {
            store.removeCoachInteraction(id: interactionID)
            cards.append(card)
        }
        cards.removeAll { $0.fingerprint == card.fingerprint }
    }
}

/// What Approve on a review card does, kept off the view so it can be pinned in a test: the
/// change is applied *first*, and only a change that took is recorded as approved (the
/// approval is what `CoachEngine.isSuppressed` keys its cool-down on).
@MainActor
enum ReviewApproval {
    enum Outcome {
        case applied(ReviewApplication, interactionID: UUID)
        case refused(String)
    }

    static func approve(card: CoachCard, change: ReviewChange?, store: WorkoutStore) -> Outcome {
        guard let change, let applied = store.applyReviewChange(change) else {
            return .refused("Couldn't apply \"\(card.title)\" — it no longer matches your plan.")
        }
        let interactionID = store.recordCoachInteraction(
            rule: card.rule, fingerprint: card.fingerprint, outcome: .approved
        )
        return .applied(applied, interactionID: interactionID)
    }

    /// The model's validated proposals, or the rules' when the model threw *or* had every
    /// proposal rejected — an empty list from the model means "nothing survived validation",
    /// not "the plan is fine", and `DebriefCard` already treats its stream the same way.
    static func proposals(fromModel: [ReviewProposal]?, digest: TrainingDigest) -> [ReviewProposal] {
        if let fromModel, !fromModel.isEmpty { return fromModel }
        return TrainingReviewRules.proposals(from: digest)
    }
}

/// Turns a validated `ReviewProposal` into the `CoachCard` the screen shows — title from the
/// change, body from the claim, the cited facts as evidence, and a `suggestedAction` so
/// `CoachCardView` can say what Approve will do.
@MainActor
enum ReviewCardBuilder {
    static func card(
        for proposal: ReviewProposal,
        digest: TrainingDigest,
        store: WorkoutStore,
        now: Date
    ) -> CoachCard {
        let name = { (id: UUID) in store.fetchExerciseModel(id: id)?.name ?? "Exercise" }
        let title: String
        let action: CoachSuggestedAction
        let key: String
        switch proposal.change {
        case .deloadLift(let id):
            title = "Deload \(name(id))"
            let history = store.exerciseHistory(exerciseID: id, limit: 1)
            let weight = history.first?.workingSets.first?.weightKg ?? 0
            let newWeight = weight * TrainingConstants.deloadLoadFraction
            action = .deloadExercise(
                exerciseName: name(id), exerciseID: id, toWeightKg: newWeight
            )
            key = "deload|\(id)"
        case .addExercise(let id):
            title = "Add \(name(id))"
            action = .addExercise(exerciseID: id, exerciseName: name(id))
            key = "add|\(id)"
        case .swapExercise(let from, let to):
            title = "Swap \(name(from)) for \(name(to))"
            action = .replaceExercise(
                exerciseID: from, exerciseName: name(from),
                withID: to, withName: name(to)
            )
            key = "swap|\(from)|\(to)"
        case .changeRepRange(let id, let low, let high):
            title = "\(name(id)): \(low)–\(high) reps"
            action = .changeRepRange(
                exerciseID: id, exerciseName: name(id),
                low: low, high: high
            )
            key = "reps|\(id)|\(low)|\(high)"
        case .changeProgressionRule(let id, let rule):
            title = "\(name(id)): \(rule.displayName)"
            action = .changeProgressionRule(
                exerciseID: id, exerciseName: name(id), rule: rule
            )
            key = "rule|\(id)|\(rule.displayName)"
        case .moveRestDay(let from, let to):
            title = "Move \(from.displayName)'s session to \(to.displayName)"
            action = .moveRestDay(from: from, to: to)
            key = "rest|\(from.rawValue)|\(to.rawValue)"
        }
        let factsByID = Dictionary(
            digest.facts.map { ($0.id, $0.text) },
            uniquingKeysWith: { first, _ in first }
        )
        let evidence = proposal.claim.citedFactIDs.compactMap { id in
            factsByID[id].map { CoachEvidenceItem(id, .text($0)) }
        }
        return CoachCard(
            rule: .trainingReview, severity: .notice, title: title, body: proposal.claim.text,
            evidence: evidence, suggestedAction: action, distinguishingKey: key, firedDate: now
        )
    }
}
