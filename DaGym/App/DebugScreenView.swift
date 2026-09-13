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
    @State private var scale = Effort.Scale.rpe
    @State private var tab = DGTab.today
    @State private var healthSync: HealthSyncService?

    var body: some View {
        Group {
            if let healthSync {
                screen.environment(healthSync)
            } else {
                AmbientWash()
            }
        }
        .task {
            // The `.rest` route is the real in-workout rest UI mid-countdown.
            if route == .rest { session.startRest(seconds: 90, after: 0, set: 0) }
            healthSync = HealthSyncService(workoutStore: store, preferences: preferences)
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
            tabbed(.library) { LibraryView() }
        case .exerciseDetail:
            NavigationStack { ExerciseDetailView(exercise: SampleData.bench) }
        case .builder:
            RoutineBuilderView(routineID: nil, onDone: {})
        case .summary:
            WorkoutSummaryView(summary: debugSummary, title: session.title, onShare: {}, onDone: {})
        case .history:
            tabbed(.progress) { HistoryTabView() }
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
            sheetHost { SwapExerciseSheet(exercise: SampleData.cableFly, onPick: { _ in }) }
        case .newExercise:
            sheetHost { NewExerciseSheet(onSave: { _ in }) }
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

    private func tabbed<Content: View>(_ selected: DGTab, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            content()
            DGTabBar(selected: .constant(selected)).padding(.bottom, 8)
        }
    }

    private func sheetHost<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ActiveWorkoutView(session: session, onFinish: { _ in })
            .sheet(isPresented: .constant(true)) { content() }
    }
}
