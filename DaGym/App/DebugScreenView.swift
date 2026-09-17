import SwiftUI
import GymCore

/// Renders one screen directly for screenshots (`-dgScreen <route>`).
/// Debug builds only. Supplies its own `HealthSyncService` so the Settings → Apple Health and
/// Body routes have the environment `RootView` would give them.
struct DebugScreenView: View {
    let route: DebugRoute
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var session = SampleData.makeSession()
    @State private var weight = 82.5
    @State private var reps = 8.0
    @State private var effort: Effort? = Effort(rpe: 8)
    @State private var scale = Effort.Scale.rpe
    @State private var healthSync: HealthSyncService?
    @State private var healthInsights: HealthInsightsService?

    var body: some View {
        Group {
            if let healthSync, let healthInsights {
                screen.environment(healthSync).environment(healthInsights)
            } else {
                AmbientWash()
            }
        }
        .task {
            // The `.rest` route is the real in-workout rest UI mid-countdown.
            if route == .rest { session.startRest(seconds: 90, after: 0, set: 0) }
            healthSync = HealthSyncService(workoutStore: store, preferences: preferences)
            healthInsights = HealthInsightsService(workoutStore: store, preferences: preferences)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch route {
        case .home:
            RootView()
        case .workout:
            ActiveWorkoutView(session: session, onFinish: { _ in })
        case .rest:
            ActiveWorkoutView(session: session, onFinish: { _ in })
        case .library:
            tabbed(.you) { LibraryView() }
        case .exerciseDetail:
            NavigationStack { ExerciseDetailView(exercise: SampleData.bench) }
        case .builder:
            RoutineBuilderView(routineID: nil, onDone: {})
        case .summary:
            WorkoutSummaryView(summary: debugSummary, title: session.title, onDone: {})
        case .history:
            tabbed(.you) { HistoryTabView() }
        case .backfill:
            sheetHost {
                BackfillSheet(
                    routines: [SampleData.pushA], onFreestyle: { _, _ in }, onRoutine: { _, _, _ in }
                )
            }
        case .keypad:
            sheetHost {
                WeightKeypadSheet(
                    title: "Bench Press", value: $weight, step: 2.5, bar: .olympic, last: "80", unit: .kg,
                    onDone: {}
                )
            }
        case .effort:
            sheetHost { EffortPickerSheet(scale: $scale, onPick: { _ in }) }
        case .swap:
            sheetHost { SwapExerciseSheet(exercise: SampleData.cableFly, onPick: { _, _ in }) }
        case .newExercise:
            sheetHost { NewExerciseSheet(onSave: { _ in }) }
        case .setKeypad:
            sheetHost {
                SetKeypadSheet(
                    exercise: SampleData.bench, set: SetEntry(weightKg: 82.5, reps: 8), setNumber: 2,
                    initialField: .weight, effortScale: scale, weight: $weight, reps: $reps, effort: $effort,
                    onLog: { _ in }
                )
            }
        case .exerciseActions:
            sheetHost {
                ExerciseActionsSheet(
                    options: .init(
                        name: SampleData.bench.name, isCardio: false, hasPrevious: false, hasNext: true,
                        isInSuperset: false
                    ),
                    onAction: { _ in }
                )
            }
        case .finish:
            sheetHost {
                FinishWorkoutSheet(prompt: "4 / 19 sets done · 25:05 elapsed", onFinish: {}, onDiscard: {})
            }
        }
    }

    /// A `WorkoutSummary` built from `SampleData.makeSession()` for the
    /// `.summary` debug route (no persisted workout exists in this path).
    private var debugSummary: WorkoutSummary {
        WorkoutSummary(
            durationSeconds: 3124, volumeKg: session.volumeKg, setsDone: session.setsDone,
            prs: session.prBanner.map { [$0] } ?? [], musclesHit: session.musclesHit
        )
    }

    /// Hosts one screen in the real system tab bar so screenshots match the shipping shell.
    private func tabbed<Content: View>(
        _ selected: DGTab, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        TabView(selection: .constant(selected)) {
            Tab(value: DGTab.today) { slot(.today, selected, content) } label: { label(.today) }
            Tab(value: DGTab.train) { slot(.train, selected, content) } label: { label(.train) }
            Tab(value: DGTab.you) { slot(.you, selected, content) } label: { label(.you) }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    @ViewBuilder
    private func slot<Content: View>(
        _ tab: DGTab, _ selected: DGTab, _ content: () -> Content
    ) -> some View {
        if tab == selected {
            content()
        } else {
            AmbientWash()
        }
    }

    private func label(_ tab: DGTab) -> some View {
        Label(tab.title, systemImage: tab.symbol)
            .accessibilityIdentifier(tab.accessibilityID)
    }

    private func sheetHost<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ActiveWorkoutView(session: session, onFinish: { _ in })
            .sheet(isPresented: .constant(true)) { content() }
    }
}
