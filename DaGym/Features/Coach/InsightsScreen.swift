import GymCore
import SwiftUI

/// Insights, pushed from the You hub and from the chat's toolbar: `CoachEngine`'s current
/// cards, most severe first, each a white card with its kicker, the claim, a "Why?" box of
/// evidence and the card's own action next to "Not now". The ten rule checks are always
/// rule-based; below them sit the two on-device coach features (`CoachReviewSection`,
/// `CoachAskSection`), which fall back to the same rules when the model isn't available. A
/// footer says which is running, so the screen never implies AI it isn't using.
struct InsightsScreen: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(CoachServices.self) private var coach
    @Environment(\.scenePhase) private var scenePhase
    @State private var cards: [CoachCard] = []
    @State private var undoAction: UndoAction?
    /// Whether anything has been logged yet — "nothing to flag" and "nothing to read" are two
    /// different empty states, and congratulating someone on consistency before their first
    /// workout reads as a machine that isn't looking.
    @State private var hasTrained = false

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s3) {
                    if hasTrained {
                        CoachReviewSection(undoAction: $undoAction)
                    }
                    if cards.isEmpty {
                        emptyState
                    } else {
                        ForEach(cards, id: \.fingerprint) { card in
                            CoachCardView(
                                card: card, formatWeight: preferences.formatWeight,
                                onApprove: { approve(card) }, onDismiss: { dismiss(card) }
                            )
                        }
                    }
                    if hasTrained {
                        CoachAskSection()
                    }
                    footer
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s10)
            }
        }
        .navigationTitle("Insights")
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .dgUndoToast($undoAction)
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .refreshOnStoreChange(refresh)
        .onReceive(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)
        ) { _ in refresh() }
        .dgWarmHaptics()
    }

    @ViewBuilder
    private var emptyState: some View {
        if hasTrained {
            EmptyState(
                symbol: "checkmark.seal",
                title: "You're on track",
                message: "No flags right now — that's what consistent training looks like. "
                    + "Check back after your next session."
            )
        } else {
            EmptyState(
                symbol: "list.bullet.clipboard",
                title: "Nothing to read yet",
                message: "These checks run on your logged sessions. Finish a workout or two and "
                    + "anything worth flagging will show up here."
            )
        }
    }

    private var footer: some View {
        Text(
            coach.isUsingLanguageModel
                ? "Ten fixed checks read your training history and flag patterns. Review and Ask "
                    + "use Apple's on-device model — it runs on your iPhone; nothing is sent anywhere."
                : "Rule-based, not AI — ten fixed checks read your training history and flag "
                    + "patterns. Nothing is sent anywhere."
        )
        .font(DGFont.footnote)
        .foregroundStyle(DGColor.ink4)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DGSpace.s1)
        .padding(.top, DGSpace.s2)
    }

    /// Rebuilds the card list from the store's current state. Called on appear, on return to
    /// foreground, at midnight and whenever the store saves while this screen is showing (a
    /// save under the active workout's cover is deferred to the next show — the ten rules plus
    /// two history fetches must not run on every logged set) — never on every render.
    private func refresh() {
        cards = store.coachCards(
            weeklyGoal: preferences.weeklyGoal, now: Date(), calendar: preferences.trainingCalendar
        )
        hasTrained = !store.workoutDates().isEmpty
    }

    /// Records the approval and, only for a deload suggestion, actually applies it (the one
    /// suggested action this adapter can carry out with no active workout to hand it to — see
    /// `WorkoutStore.applyCoachDeload`). Every other suggested action is recorded honestly as
    /// "seen and agreed with" without pretending to act on it.
    ///
    /// Undoable, like Not now: the action button is the one that actually changes the lifter's
    /// plan, so it had the stronger claim on an Undo of the two. Undo puts back both the plan
    /// targets and the recorded approval.
    private func approve(_ card: CoachCard) {
        let interactionID = store.recordCoachInteraction(
            rule: card.rule, fingerprint: card.fingerprint, outcome: .approved
        )
        var applied: CoachDeloadApplication?
        var plannedWeek = false
        switch card.suggestedAction {
        case .deloadExercise(let name, let exerciseID, let toWeightKg):
            applied = store.applyCoachDeload(
                exerciseID: exerciseID, exerciseName: name, toWeightKg: toWeightKg
            )
        case .planDeloadWeek:
            store.planDeloadWeek()
            plannedWeek = true
        default:
            break
        }
        let message = applied.map {
            "\($0.exerciseName) set to \(preferences.formatWeight(kg: $0.weightKg))"
        } ?? (plannedWeek ? "Deload week planned" : "Approved \"\(card.title)\"")
        undoAction = UndoAction(message: message) {
            if let applied { store.undoCoachDeload(applied) }
            if plannedWeek { store.cancelPlannedDeloadWeek() }
            store.removeCoachInteraction(id: interactionID)
            refresh()
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
        NavigationStack { InsightsScreen() }
            .environment(store)
            .environment(Preferences())
            .environment(CoachServices.make(preferences: Preferences()))
    } else {
        Text("Preview unavailable")
    }
}
