import SwiftData
import SwiftUI

/// The Progress tab content: history list + backfill entry point + workout
/// detail navigation, all driven by the store.
struct HistoryTabView: View {
    @Environment(WorkoutStore.self) private var store

    @State private var records: [WorkoutRecord] = []
    @State private var routines: [RoutineInfo] = []
    @State private var workoutsCount = 0
    @State private var volumeKg: Double = 0
    @State private var showingBackfill = false
    @State private var backfillSession: WorkoutSession?
    @State private var finishedWorkout: FinishedWorkout?

    var body: some View {
        NavigationStack {
            HistoryView(
                records: records, workoutsCount: workoutsCount, volumeKg: volumeKg,
                onBackfill: { showingBackfill = true }, onDelete: deleteWorkout
            )
            .navigationDestination(for: UUID.self) { id in
                WorkoutDetailView(workoutID: id)
            }
        }
        .task { refresh() }
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(onFreestyle: startFreestyleBackfill, onRoutine: startRoutineBackfill)
        }
        .fullScreenCover(item: $backfillSession) { session in
            ActiveWorkoutView(session: session) { summary in
                let title = session.title
                backfillSession = nil
                finishedWorkout = FinishedWorkout(summary: summary, title: title)
            }
        }
        .fullScreenCover(item: $finishedWorkout) { finished in
            WorkoutSummaryView(
                summary: finished.summary, title: finished.title, onShare: {},
                onDone: { finishedWorkout = nil; refresh() }
            )
        }
    }

    private func refresh() {
        records = store.history()
        let stats = store.lifetimeStats()
        workoutsCount = stats.workouts
        volumeKg = stats.volumeKg
        routines = store.routines()
    }

    private func deleteWorkout(_ id: UUID) {
        store.deleteWorkout(id: id)
        refresh()
    }

    private func startFreestyleBackfill(date: Date, minutes: Int) {
        showingBackfill = false
        backfillSession = store.startBackfill(date: date, durationMinutes: minutes, routineID: nil)
    }

    /// Matches `RootView`'s backfill-to-routine behaviour: no routine picker in the sheet
    /// yet, so the most recently used routine is backfilled against.
    private func startRoutineBackfill(date: Date, minutes: Int) {
        showingBackfill = false
        let routineID = routines.first?.id
        backfillSession = store.startBackfill(date: date, durationMinutes: minutes, routineID: routineID)
    }
}

/// Wraps a finished backfill's summary so it can drive a `fullScreenCover(item:)`.
private struct FinishedWorkout: Identifiable {
    let id = UUID()
    var summary: WorkoutSummary
    var title: String
}

#Preview {
    if let store = PreviewStore.make() {
        HistoryTabView()
            .environment(store)
    }
}
