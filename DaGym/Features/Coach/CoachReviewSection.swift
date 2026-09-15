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

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack {
                Text("Review").dgLabel()
                Spacer()
                Button(isReviewing ? "Reviewing…" : "Review my training") { Task { await review() } }
                    .buttonStyle(.dgControl)
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
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
        }
    }

    private func review() async {
        isReviewing = true
        defer { isReviewing = false; hasReviewed = true }
        let now = Date()
        let digest = store.trainingDigest(now: now, calendar: preferences.trainingCalendar)
        let proposals: [ReviewProposal]
        if let fromModel = try? await coach.model.reviewTraining(digest: digest) {
            proposals = fromModel
        } else {
            proposals = TrainingReviewRules.proposals(from: digest)
        }
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
        let interactionID = store.recordCoachInteraction(
            rule: card.rule, fingerprint: card.fingerprint, outcome: .approved
        )
        let applied = changes[card.fingerprint].flatMap(store.applyReviewChange)
        undoAction = UndoAction(message: applied?.message ?? "Approved \"\(card.title)\"") {
            if let applied { store.undoReviewChange(applied) }
            store.removeCoachInteraction(id: interactionID)
            cards.append(card)
        }
        cards.removeAll { $0.fingerprint == card.fingerprint }
    }

    private func dismiss(_ card: CoachCard) {
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
