import Foundation
import GymCore
import WidgetKit

/// The watch's stand-in for the phone's `WidgetSnapshotWriter`: the shared `WorkoutStore` calls
/// `refresh(store:)` after `finish(session:)`, `saveRoutine` and `deleteRoutine`, and here that
/// rewrites the `WatchSnapshot` the complications read. Same name and signature so the store
/// compiles unchanged on both platforms.
@MainActor
enum WidgetSnapshotWriter {
    static func refresh(store: WorkoutStore) {
        WatchSnapshotWriter.refresh(store: store, rest: nil)
    }
}

/// Builds and writes the `WatchSnapshot`, reloading the widget timelines only when the content
/// changed (WidgetKit's daily reload budget is small on the wrist).
@MainActor
enum WatchSnapshotWriter {
    static func refresh(store: WorkoutStore, rest: WatchSnapshot.Rest?, now: Date = Date()) {
        guard !WatchLaunchFlags.isSample, let suite = WatchSnapshotStore.appGroupSuite else { return }
        var next = snapshot(store: store, now: now)
        next.rest = rest
        let current = WatchSnapshotStore.read(from: suite)
        guard next != current else { return }
        WatchSnapshotStore.write(next, to: suite)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func snapshot(store: WorkoutStore, now: Date = Date()) -> WatchSnapshot {
        let calendar = Calendar.current
        let dates = store.finishedWorkoutModelsNewestFirst().map(\.startedAt)
        let streak = Streaks.weekly(
            workoutDates: dates, weeklyGoal: WatchPreferences.weeklyGoal, calendar: calendar, now: now
        )
        var snapshot = WatchSnapshot(streakWeeks: streak.current)
        snapshot.trainedThisWeek = trainedDays(dates, calendar: calendar, now: now)
        if let today = store.todaysRoutine(calendar: calendar, now: now) {
            snapshot.nextRoutineName = today.name
            snapshot.nextSessionDate = calendar.date(
                bySettingHour: WatchPreferences.scheduledStartHour, minute: 0, second: 0, of: now
            )
            snapshot.isNextToday = true
        } else if let next = store.nextSession(calendar: calendar, now: now) {
            snapshot.nextRoutineName = next.routine.name
            snapshot.nextSessionDate = calendar.date(
                bySettingHour: WatchPreferences.scheduledStartHour, minute: 0, second: 0, of: next.date
            )
        }
        return snapshot
    }

    /// Seven flags, first weekday first, true on each day this week that had a session.
    static func trainedDays(_ dates: [Date], calendar: Calendar, now: Date) -> [Bool] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return Array(repeating: false, count: 7)
        }
        let trained = Set(dates.map { calendar.startOfDay(for: $0) })
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return false }
            return trained.contains(calendar.startOfDay(for: day))
        }
    }
}
