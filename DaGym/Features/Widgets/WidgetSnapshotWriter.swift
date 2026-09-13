import Foundation
import GymCore
import WidgetKit

/// Writes the current `WidgetSnapshot` to the App Group after every finish/schedule change and
/// reloads the widget timelines. Called from `WorkoutStore.finish(session:)` and from
/// `WorkoutStore.saveRoutine`/`deleteRoutine` (a routine save/delete can change which routine
/// `routines().first` — "today's" routine — resolves to).
@MainActor
enum WidgetSnapshotWriter {
    /// Falls back to the documented default (`Preferences.defaultRestSeconds`'s sibling default)
    /// when a caller has no `Preferences` in scope, matching `Preferences`'s own default.
    private static let fallbackWeeklyGoal = 4

    static func refresh(store: WorkoutStore, suite: UserDefaults? = WidgetSnapshotStore.appGroupSuite) {
        guard let suite else { return }
        let calendar = Calendar.current
        let now = Date()
        let dates = store.workoutDates()
        let weeklyGoal = UserDefaults.standard.object(forKey: "weeklyGoal") as? Int ?? fallbackWeeklyGoal
        let streak = Streaks.weekly(workoutDates: dates, weeklyGoal: weeklyGoal, calendar: calendar, now: now)
        let routine = store.routines().first
        let snapshot = WidgetSnapshot(
            routineName: routine?.name, exerciseCount: routine?.exercises.count ?? 0,
            streakWeeks: streak.current, trainedDays: trainedDays(dates: dates, calendar: calendar, now: now),
            updatedAt: now
        )
        WidgetSnapshotStore.write(snapshot, to: suite)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Last 7 calendar days, oldest first, `true` where at least one finished workout landed.
    private static func trainedDays(dates: [Date], calendar: Calendar, now: Date) -> [Bool] {
        (0..<7).reversed().map { offset -> Bool in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return false }
            return dates.contains { calendar.isDate($0, inSameDayAs: day) }
        }
    }
}
