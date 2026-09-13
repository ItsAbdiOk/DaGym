import SwiftUI
import GymCore

/// Renders one screen directly for screenshots (`-dgScreen <route>`).
/// Debug builds only.
struct DebugScreenView: View {
    let route: DebugRoute
    @State private var session = SampleData.makeSession()
    @State private var weight = 82.5
    @State private var scale = Effort.Scale.rpe
    @State private var tab = DGTab.today

    var body: some View {
        switch route {
        case .home:
            RootView()
        case .workout:
            ActiveWorkoutView(session: session, onFinish: { _ in })
        case .rest:
            RestTimerView(session: session, exerciseName: "Bench Press", onClose: {})
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
            sheetHost { BackfillSheet(onFreestyle: { _, _ in }, onRoutine: { _, _ in }) }
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
