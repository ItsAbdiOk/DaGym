import GymCore
import SwiftUI

/// The Coach tab (plan.md phase 6): lists `CoachEngine`'s current cards, most severe first, with
/// Approve/Dismiss on every one — replaces `CoachPlaceholderView`. Rule-based only, never AI (see
/// `header`'s disclaimer): the on-device AI coach is a separate, later feature and this screen
/// must not imply it.
struct CoachView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @State private var cards: [CoachCard] = []
    @State private var expanded: Set<String> = []
    @State private var undoAction: UndoAction?

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s5) {
                    header
                    if cards.isEmpty {
                        EmptyState(
                            symbol: "checkmark.seal",
                            title: "You're On Track",
                            message: "No flags right now — that's what consistent training looks "
                                + "like. Check back after your next session."
                        )
                    } else {
                        ForEach(cards, id: \.fingerprint) { card in
                            CoachCardView(
                                card: card, isExpanded: expanded.contains(card.fingerprint),
                                formatWeight: preferences.formatWeight,
                                onToggle: { toggle(card) }, onApprove: { approve(card) },
                                onDismiss: { dismiss(card) }
                            )
                        }
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s10)
            }
        }
        .dgUndoToast($undoAction)
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onChange(of: store.changeToken) { _, _ in refresh() }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)
        ) { _ in refresh() }
        .dgWarmHaptics()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Coach")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text(
                "Rule-based, not AI — ten fixed checks read your training history and flag "
                    + "patterns. Nothing is sent anywhere."
            )
            .font(DGFont.footnote)
            .foregroundStyle(DGColor.ink4)
        }
    }

    /// Rebuilds the card list from the store's current state. Called on appear, on return to
    /// foreground, at midnight and whenever the store saves (a workout finishing included) —
    /// never on every render, matching `RootView.refresh()`'s own triggers.
    private func refresh() {
        cards = store.coachCards(
            weeklyGoal: preferences.weeklyGoal, now: Date(), calendar: preferences.trainingCalendar
        )
    }

    private func toggle(_ card: CoachCard) {
        if expanded.contains(card.fingerprint) {
            expanded.remove(card.fingerprint)
        } else {
            expanded.insert(card.fingerprint)
        }
    }

    /// Records the approval and, only for a deload suggestion, actually applies it (the one
    /// suggested action this adapter can carry out with no active workout to hand it to — see
    /// `WorkoutStore.applyCoachDeload`). Every other suggested action is recorded honestly as
    /// "seen and agreed with" without pretending to act on it.
    private func approve(_ card: CoachCard) {
        store.recordCoachInteraction(rule: card.rule, fingerprint: card.fingerprint, outcome: .approved)
        if case .deloadExercise(let exerciseName, let toWeightKg, _) = card.suggestedAction {
            store.applyCoachDeload(exerciseName: exerciseName, toWeightKg: toWeightKg)
        }
        refresh()
    }

    private func dismiss(_ card: CoachCard) {
        let interactionID = store.recordCoachInteraction(
            rule: card.rule, fingerprint: card.fingerprint, outcome: .dismissed
        )
        undoAction = UndoAction(message: "Dismissed \"\(card.title)\"") {
            store.removeCoachInteraction(id: interactionID)
            refresh()
        }
        refresh()
    }
}

#Preview {
    if let store = PreviewStore.make() {
        CoachView()
            .environment(store)
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
