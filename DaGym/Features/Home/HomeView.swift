import GymCore
import SwiftData
import SwiftUI

/// Home / Today — the app's landing screen. The redesign's hero card (today's routine or the
/// rest day), the week / bodyweight tiles, the recovery row and the coach's nudges, all
/// computed from real workout history. The streak moved to the You tab with the redesign.
struct HomeView: View {
    var routine: RoutineInfo?
    /// "Next: Pull B · Thursday" for the rest-day card, from `WorkoutStore.nextSession()`.
    /// `nil` when nothing is scheduled within the lookahead window.
    var nextSessionText: String?
    var onStart: () -> Void
    var onFreestyle: () -> Void
    var onBackfill: () -> Void
    var onSeeRecovery: () -> Void
    var onOpenBody: () -> Void
    /// "Pick another routine" in the start sheet switches the shell to the Train tab.
    var onShowTrain: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var thisWeekCount = 0
    @State private var recoveryMap: [Muscle: Double] = [:]
    @State private var showingGymCard = false
    @State private var showingStartSheet = false
    /// The start sheet's rows dismiss first and act on `onDismiss`, so the coach chat (a
    /// full-screen cover) never tries to present on top of a sheet that is still going away.
    @State private var pendingStartAction: (() -> Void)?
    @State private var askingCoach = false
    @State private var deloadSuggestion: DeloadSuggestionInfo?
    @State private var hasSchedule = true
    @State private var hasAnyRoutines = true
    @State private var otherRoutineNames: [String] = []
    @State private var bodyweightKg: Double?
    @State private var bodyweightDeltaKg: Double?

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s3) {
                    header
                    if preferences.sampleDataMode {
                        SampleDataBanner(onClear: clearSampleData)
                    }
                    heroCard
                    // Directly under the hero, not at the foot of the page: the strip's "Plan"
                    // button sits at the trailing edge, exactly where the floating start
                    // button lands when the strip is the last card in view.
                    if let deloadSuggestion {
                        DeloadStrip(
                            reason: deloadSuggestion.reason, onPlan: planDeload, onSnooze: snoozeDeload
                        )
                    }
                    // Side by side normally; one under the other at accessibility sizes, where
                    // two half-width tiles squeezed "BODYWEIGHT" into mid-word wraps.
                    DGAdaptiveStack(spacing: 10) {
                        WeekTile(done: thisWeekCount, total: preferences.weeklyGoal)
                        BodyweightTile(kg: bodyweightKg, deltaKg: bodyweightDeltaKg, onTap: onOpenBody)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    RecoveryRow(map: recoveryMap, onSeeRecovery: onSeeRecovery)
                    WeekReviewCard()
                }
                .padding(.horizontal, DGSpace.s4)
                // Clears the floating tab bar and the FAB `RootView` draws over this tab.
                .padding(.bottom, 110)
            }
        }
        .dgWarmHaptics()
        .task { refresh() }
        .refreshOnStoreChange(refresh)
        .onChange(of: preferences.weeklyGoal) { refresh() }
        .onChange(of: preferences.weekStartsMonday) { refresh() }
        .sheet(isPresented: $showingGymCard) { GymCardSheet() }
        .sheet(isPresented: $showingStartSheet, onDismiss: runPendingStartAction) {
            StartSomethingElseSheet(
                routineNames: otherRoutineNames,
                onFreestyle: { deferStart(onFreestyle) },
                onBackfill: { deferStart(onBackfill) },
                onPickRoutine: { deferStart(onShowTrain) },
                onAskCoach: { deferStart { askingCoach = true } }
            )
        }
        .askCoach(on: $askingCoach)
    }

    @ViewBuilder private var heroCard: some View {
        if !hasAnyRoutines {
            StarterPlanCard(
                onPick: pickStarterPlan, onAskCoach: { askingCoach = true }, onFreestyle: onFreestyle
            )
        } else if let routine {
            HomeHeroCard(
                variant: .scheduled(routine: routine, isScheduled: hasSchedule),
                onPrimary: onStart, onMore: { showingStartSheet = true }, onBodyMap: onSeeRecovery
            )
        } else {
            HomeHeroCard(
                variant: .rest(nextSessionText: nextSessionText),
                onPrimary: onFreestyle, onMore: { showingStartSheet = true }, onBodyMap: onSeeRecovery
            )
        }
    }

    /// The scheduled routine itself comes from `RootView` (it owns "Start"); everything else
    /// is one `HomeSnapshot` pass so the numbers agree with the widget and the You tab.
    private func refresh() {
        let snapshot = HomeSnapshot.make(store: store, preferences: preferences)
        thisWeekCount = snapshot.thisWeekCount
        recoveryMap = snapshot.recoveryMap
        deloadSuggestion = snapshot.deloadSuggestion
        hasSchedule = snapshot.hasSchedule
        hasAnyRoutines = snapshot.hasAnyRoutines
        otherRoutineNames = snapshot.otherRoutineNames
        bodyweightKg = snapshot.bodyweightKg
        bodyweightDeltaKg = snapshot.bodyweightDeltaKg
    }

    private func deferStart(_ action: @escaping () -> Void) {
        pendingStartAction = action
        showingStartSheet = false
    }

    private func runPendingStartAction() {
        let action = pendingStartAction
        pendingStartAction = nil
        action?()
    }

    /// Builds and starts `kind`'s starter program in one tap (Home's empty-state card) —
    /// `store.changeToken` refreshes this view, `RootView` and the widget once it lands.
    private func pickStarterPlan(_ kind: StarterProgramKind) {
        store.adoptStarterPlan(kind)
    }

    private func clearSampleData() {
        SampleDataSeeder.clear(store: store, preferences: preferences)
    }

    private func planDeload() {
        store.planDeloadWeek()
        deloadSuggestion = nil
    }

    /// "Not now": snoozes the whole card for a week *and* records the dismissal against this
    /// evidence in the same store the Coach tab reads, so the identical card doesn't just
    /// reappear one tab over (`WorkoutStore.dismissDeloadSuggestion`).
    private func snoozeDeload() {
        preferences.deloadSnoozedUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        if let deloadSuggestion { store.dismissDeloadSuggestion(deloadSuggestion) }
        deloadSuggestion = nil
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Self.todayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.ink3)
                Text("Today")
                    .font(DGFont.title1)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer()
            DGIconButton(symbol: "barcode", size: 38, accessibilityLabel: "Gym card") {
                showingGymCard = true
            }
            .accessibilityIdentifier(A11yID.homeGymCard)
            .padding(.top, 6)
        }
        .padding(.horizontal, DGSpace.s1)
        .padding(.bottom, DGSpace.s2)
    }

    private static var todayLabel: String { todayFormatter.string(from: Date()) }

    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        HomeView(
            routine: SampleData.pushA, onStart: {}, onFreestyle: {}, onBackfill: {},
            onSeeRecovery: {}, onOpenBody: {}, onShowTrain: {}
        )
        .environment(WorkoutStore(context: container.mainContext))
        .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}

#Preview("Rest day") {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        HomeView(
            routine: nil, nextSessionText: "Next: Pull B · Thursday", onStart: {}, onFreestyle: {},
            onBackfill: {}, onSeeRecovery: {}, onOpenBody: {}, onShowTrain: {}
        )
        .environment(WorkoutStore(context: container.mainContext))
        .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
