import Foundation
import GymCore
import WidgetKit

/// Writes the current `WidgetSnapshot` to the App Group and reloads the widget timelines.
/// Called from `WorkoutStore.finish(session:)`, `saveRoutine`/`deleteRoutine`, the schedule
/// editor and `RootView`'s foreground/day-change hooks. "Today's routine" is the same
/// `WorkoutStore.todaysRoutine()` Home shows, and "this week" the same `Preferences.trainingCalendar`.
///
/// A no-op in a test process: unit tests finish workouts by the dozen and must not overwrite the
/// developer's real widget or spend the timeline-reload budget. Tests build snapshots through
/// `snapshot(store:preferences:now:)` or inject a suite and `isTesting: false`.
@MainActor
struct WidgetSnapshotWriter {
    var suite: UserDefaults?
    var isTesting: Bool
    var reloadTimelines: @MainActor () -> Void

    static var live: WidgetSnapshotWriter {
        WidgetSnapshotWriter(
            suite: WidgetSnapshotStore.appGroupSuite, isTesting: LaunchFlags.isTesting,
            reloadTimelines: { WidgetCenter.shared.reloadAllTimelines() }
        )
    }

    /// The app's own preferences (`UserDefaults.standard`) unless the caller has an instance.
    static func refresh(store: WorkoutStore, preferences: Preferences? = nil) {
        live.refresh(store: store, preferences: preferences ?? Preferences())
    }

    /// Writes only when something the widget shows actually changed, so calling this on every
    /// foreground doesn't burn WidgetKit's daily reload budget.
    func refresh(store: WorkoutStore, preferences: Preferences, now: Date = Date()) {
        guard !isTesting, let suite else { return }
        let next = Self.snapshot(store: store, preferences: preferences, now: now)
        let current = WidgetSnapshotStore.read(from: suite)
        guard !next.sameContent(as: current) else { return }
        WidgetSnapshotStore.write(next, to: suite)
        reloadTimelines()
    }

    static func snapshot(
        store: WorkoutStore, preferences: Preferences, now: Date = Date()
    ) -> WidgetSnapshot {
        let calendar = preferences.trainingCalendar
        let dates = store.workoutDates()
        let streak = Streaks.weekly(
            workoutDates: dates, weeklyGoal: preferences.weeklyGoal, calendar: calendar, now: now
        )
        let routine = store.todaysRoutine(calendar: calendar, now: now)
        return WidgetSnapshot(
            routineName: routine?.name, exerciseCount: routine?.exercises.count ?? 0,
            streakWeeks: streak.current, trainedDays: trainedDays(dates: dates, calendar: calendar, now: now),
            updatedAt: now, routineSymbolName: routine?.symbolName, routineTint: routine?.tint
        )
    }

    /// Last 7 calendar days, oldest first, `true` where at least one finished workout landed.
    private static func trainedDays(dates: [Date], calendar: Calendar, now: Date) -> [Bool] {
        (0..<7).reversed().map { offset -> Bool in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return false }
            return dates.contains { calendar.isDate($0, inSameDayAs: day) }
        }
    }
}

extension WidgetSnapshot {
    /// Equality ignoring `updatedAt` — what the widget would actually render differently.
    func sameContent(as other: WidgetSnapshot) -> Bool {
        routineName == other.routineName && exerciseCount == other.exerciseCount
            && streakWeeks == other.streakWeeks && trainedDays == other.trainedDays
            && routineSymbolName == other.routineSymbolName && routineTint == other.routineTint
    }
}
