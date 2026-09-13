import GymCore
import SwiftData
import SwiftUI

/// The Progress tab content: history list + backfill entry point + workout
/// detail navigation, all driven by the store.
struct HistoryTabView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var records: [WorkoutRecord] = []
    @State private var routines: [RoutineInfo] = []
    @State private var workoutsCount = 0
    @State private var volumeKg: Double = 0
    @State private var recordsCount = 0
    @State private var recoveryHeadline = ""
    @State private var currentStreakWeeks = 0
    @State private var showingBackfill = false
    @State private var backfillSession: WorkoutSession?
    @State private var finishedWorkout: FinishedWorkout?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    ProgressChartsSection()
                        .padding(.horizontal, DGSpace.s4)
                        .padding(.top, DGSpace.s3)
                        .padding(.bottom, DGSpace.s2)
                }
                .frame(maxHeight: 380)
                HistoryView(
                    records: records, workoutsCount: workoutsCount, volumeKg: volumeKg,
                    recordsCount: recordsCount, recoveryHeadline: recoveryHeadline,
                    currentStreakWeeks: currentStreakWeeks,
                    onBackfill: { showingBackfill = true }, onDelete: deleteWorkout
                )
                .frame(maxHeight: .infinity)
            }
            .navigationDestination(for: UUID.self) { id in
                WorkoutDetailView(workoutID: id)
            }
        }
        .task { refresh() }
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(
                routines: routines, onFreestyle: startFreestyleBackfill, onRoutine: startRoutineBackfill
            )
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
        recordsCount = store.personalRecords().reduce(0) { $0 + $1.records.count }
        recoveryHeadline = Recovery.headline(map: store.recoverySnapshot().map).title
        currentStreakWeeks = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: preferences.weeklyGoal,
            calendar: Calendar.current, now: Date()
        ).current
    }

    private func deleteWorkout(_ id: UUID) {
        store.deleteWorkout(id: id)
        refresh()
    }

    private func startFreestyleBackfill(date: Date, minutes: Int) {
        showingBackfill = false
        backfillSession = store.startBackfill(date: date, durationMinutes: minutes, routineID: nil)
        backfillSession?.effortScale = preferences.effortScale
    }

    private func startRoutineBackfill(date: Date, minutes: Int, routineID: UUID) {
        showingBackfill = false
        backfillSession = store.startBackfill(date: date, durationMinutes: minutes, routineID: routineID)
        backfillSession?.effortScale = preferences.effortScale
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
            .environment(Preferences())
    }
}
