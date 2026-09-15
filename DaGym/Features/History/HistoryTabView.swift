import GymCore
import OSLog
import SwiftData
import SwiftUI

/// The Progress tab content: history list, month calendar, backfill entry point (with a
/// same-day conflict choice), undo-able delete and workout detail navigation, all driven by
/// the store.
struct HistoryTabView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var records: [WorkoutRecord] = []
    @State private var groups: [HistoryWeekGroup] = []
    @State private var routines: [RoutineInfo] = []
    @State private var workoutsCount = 0
    @State private var volumeKg: Double = 0
    @State private var recordsCount = 0
    @State private var recoveryHeadline = ""
    @State private var currentStreakWeeks = 0
    @State private var schedule = WeeklySchedule()
    @State private var showingBackfill = false
    @State private var backfillDate = Date()
    @State private var showingCalendar = false
    @State private var path: [UUID] = []
    @State private var undo: UndoAction?
    @State private var backfillSession: WorkoutSession?
    @State private var finishedWorkout: FinishedWorkout?
    /// A store change landed while this tab's own backfill cover was up (`store.sync` bumps the
    /// token per set); paid once when the cover goes away rather than per tap underneath it.
    @State private var needsRefresh = false
    /// Bumped by every `refresh()`; `ProgressChartsSection` re-reads its series when it changes,
    /// so the weekly-volume chart follows a delete/undo/backfill instead of going stale.
    @State private var chartsGeneration = 0

    private static let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

    var body: some View {
        NavigationStack(path: $path) {
            HistoryView(
                groups: groups, workoutsCount: workoutsCount, volumeKg: volumeKg,
                recordsCount: recordsCount, recoveryHeadline: recoveryHeadline,
                currentStreakWeeks: currentStreakWeeks,
                onBackfill: { beginBackfill(date: Date()) }, onDelete: deleteWorkout,
                onCalendar: { showingCalendar = true },
                charts: AnyView(ProgressChartsSection(generation: chartsGeneration))
            )
            .navigationDestination(for: UUID.self) { id in
                WorkoutDetailView(workoutID: id)
            }
        }
        .dgUndoToast($undo)
        // The charts section runs its own first read on appearance; bumping here would double it.
        .task { refresh(reloadCharts: false) }
        // Health auto-imports, CloudKit merges and photo deletes all bump the token while this
        // tab sits on screen; without this the list only caught up on the next tab switch.
        // Tab visibility is handled by the modifier; the local backfill cover is handled here.
        .refreshOnStoreChange {
            if backfillSession == nil, finishedWorkout == nil {
                refresh()
            } else {
                needsRefresh = true
            }
        }
        // A discarded backfill dismisses without `onDone`; a finished one refreshes there.
        .onChange(of: backfillSession?.id) { _, _ in
            if backfillSession == nil, finishedWorkout == nil, needsRefresh { refresh() }
        }
        // The buckets depend on the week start and on which week "now" falls in.
        .onChange(of: preferences.weekStartsMonday) { _, _ in regroup() }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)
        ) { _ in regroup() }
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(
                routines: routines, initialDate: backfillDate, records: records,
                onFreestyle: startFreestyleBackfill, onRoutine: startRoutineBackfill,
                onReplace: replaceWorkouts
            )
        }
        .sheet(isPresented: $showingCalendar) {
            MonthCalendarSheet(
                records: records, schedule: schedule, routines: routines,
                onOpenWorkout: { path = [$0] }, onBackfill: beginBackfill, onMove: moveSession
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
                summary: finished.summary, title: finished.title,
                onDone: { finishedWorkout = nil; refresh() }
            )
        }
    }

    private func refresh(reloadCharts: Bool = true) {
        let state = Self.signposter.beginInterval("HistoryTabView.refresh")
        defer { Self.signposter.endInterval("HistoryTabView.refresh", state) }
        needsRefresh = false
        if reloadCharts { chartsGeneration += 1 }
        records = store.history()
        regroup()
        let stats = store.lifetimeStats()
        workoutsCount = stats.workouts
        volumeKg = stats.volumeKg
        routines = store.routines()
        schedule = store.schedule()
        recordsCount = store.personalRecords().reduce(0) { $0 + $1.records.count }
        recoveryHeadline = Recovery.headline(map: store.recoverySnapshot().map).title
        currentStreakWeeks = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: preferences.weeklyGoal,
            calendar: preferences.trainingCalendar, now: Date()
        ).current
    }

    /// Buckets `records` into week/month sections once, so `HistoryView` renders a ready list.
    private func regroup() {
        groups = HistoryView.weekGroups(records: records, now: Date(), calendar: preferences.trainingCalendar)
    }

    private func deleteWorkout(_ id: UUID) {
        guard let snapshot = store.deleteWorkout(id: id) else { return }
        refresh()
        undo = UndoAction(message: "Deleted workout") {
            store.restoreWorkout(snapshot)
            refresh()
        }
    }

    /// "Replace" from the backfill conflict dialog: the day's existing workouts go before the
    /// new one is logged.
    private func replaceWorkouts(_ ids: [UUID]) {
        for id in ids {
            store.deleteWorkout(id: id)
        }
        refresh()
    }

    private func beginBackfill(date: Date) {
        backfillDate = date
        showingBackfill = true
    }

    /// From the calendar sheet: the source day becomes rest and `routineIDs` land on `newDate`.
    private func moveSession(from sourceDate: Date, to newDate: Date, routineIDs: [UUID]) {
        var updated = schedule
        updated.moved(date: sourceDate, toRoutines: [])
        updated.moved(date: newDate, toRoutines: routineIDs)
        store.saveSchedule(updated)
        WidgetSnapshotWriter.refresh(store: store, preferences: preferences)
        // Same reason as `ScheduleView.persist`: the moved day's reminder has to move with it.
        TrainingNotificationScheduler().rescheduleAll(store: store, preferences: preferences)
        // …and so does its calendar event. Moving a session from here saved the schedule but
        // never synced, so the "DaGym" calendar kept showing the session on the old day until
        // something else happened to trigger a sync.
        CalendarSyncCoordinator.syncInBackground(store: store, preferences: preferences)
        refresh()
    }

    private func startFreestyleBackfill(date: Date, minutes: Int) {
        showingBackfill = false
        backfillSession = store.startBackfill(
            date: date, durationMinutes: minutes, routineID: nil,
            calendar: preferences.trainingCalendar
        )
        backfillSession?.effortScale = preferences.effortScale
    }

    private func startRoutineBackfill(date: Date, minutes: Int, routineID: UUID) {
        showingBackfill = false
        backfillSession = store.startBackfill(
            date: date, durationMinutes: minutes, routineID: routineID,
            calendar: preferences.trainingCalendar
        )
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
