import Foundation
import GymCore
import WidgetKit

/// Writes the current `WidgetSnapshot` to the App Group and reloads the widget timelines.
/// Called from `WorkoutStore.finish(session:)`, `saveRoutine`/`deleteRoutine`, the schedule
/// editor and `RootView`'s foreground/day-change hooks. "Today's routine" is the same
/// `WorkoutStore.todaysRoutine()` Home shows, and "this week" the same `Preferences.trainingCalendar`.
///
/// Deliberately *not* wired to `WorkoutStore.changeToken`: this is a full history fetch plus a
/// streak recompute, and every logged set bumps that token.
///
/// A no-op in a test process: unit tests finish workouts by the dozen and must not overwrite the
/// developer's real widget or spend the timeline-reload budget. Tests build snapshots through
/// `snapshot(store:preferences:now:)` or inject a suite and `isTesting: false`.
@MainActor
struct WidgetSnapshotWriter {
    /// How many days of plan the snapshot carries. The timeline emits one entry per midnight
    /// inside this window, so it also bounds how long the widget stays true with the app closed.
    static let horizonDays = 8
    /// How far back workout days are kept, for the dot row and the weekly streak.
    private static let historyDays = 400

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
        let workoutDays = self.workoutDays(store: store, calendar: calendar, now: now)
        let streak = Streaks.weekly(
            workoutDates: workoutDays, weeklyGoal: preferences.weeklyGoal, calendar: calendar, now: now
        )
        let days = plannedDays(store: store, calendar: calendar, now: now)
        let today = days.first
        return WidgetSnapshot(
            routineName: today?.routineName, exerciseCount: today?.exerciseCount ?? 0,
            streakWeeks: streak.current,
            trainedDays: WidgetSnapshot.trainedDays(workoutDays, endingOn: now, calendar: calendar),
            updatedAt: now, routineSymbolName: today?.routineSymbolName,
            routineTint: today?.routineTint, days: days, workoutDays: workoutDays,
            weeklyGoal: preferences.weeklyGoal, weekStartsMonday: preferences.weekStartsMonday,
            accent: preferences.accent.rawValue, appearance: preferences.appearance.rawValue
        )
    }

    /// Today plus the next `horizonDays - 1` days. Reads the schedule and routine list once and
    /// applies `todaysRoutines`' own rule (per-date overrides win; an empty schedule falls back to
    /// the first routine) rather than re-fetching the store eight times.
    private static func plannedDays(
        store: WorkoutStore, calendar: Calendar, now: Date
    ) -> [WidgetDayPlan] {
        let schedule = store.schedule()
        let routines = store.routines()
        let hasPlan = !schedule.dayRoutines.isEmpty || !schedule.dateOverrides.isEmpty
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<horizonDays).compactMap { offset -> WidgetDayPlan? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else {
                return nil
            }
            let routine: RoutineInfo? = hasPlan
                ? schedule.routineIDs(on: day, calendar: calendar)
                    .compactMap { id in routines.first { $0.id == id } }.first
                : routines.first
            return WidgetDayPlan(
                date: day, routineName: routine?.name, exerciseCount: routine?.exercises.count ?? 0,
                routineSymbolName: routine?.symbolName, routineTint: routine?.tint
            )
        }
    }

    /// Start-of-day of every finished workout in the last `historyDays`, deduplicated.
    private static func workoutDays(store: WorkoutStore, calendar: Calendar, now: Date) -> [Date] {
        let cutoff = calendar.date(byAdding: .day, value: -historyDays, to: now) ?? .distantPast
        let days = store.workoutDates().filter { $0 >= cutoff }.map { calendar.startOfDay(for: $0) }
        return Array(Set(days)).sorted()
    }
}

extension WidgetSnapshot {
    /// Equality ignoring `updatedAt` — what the widget would actually render differently, now
    /// including the look-ahead, the history behind the streak, and the user's theme.
    func sameContent(as other: WidgetSnapshot) -> Bool {
        routineName == other.routineName && exerciseCount == other.exerciseCount
            && streakWeeks == other.streakWeeks && trainedDays == other.trainedDays
            && routineSymbolName == other.routineSymbolName && routineTint == other.routineTint
            && days == other.days && workoutDays == other.workoutDays
            && weeklyGoal == other.weeklyGoal && weekStartsMonday == other.weekStartsMonday
            && accent == other.accent && appearance == other.appearance
    }
}
