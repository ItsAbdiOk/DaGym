import Foundation
import GymCore

/// Everything Home computes from the store in one pass: today's routine (or the rest-day
/// headline), streak, weekly count, recovery map and deload suggestion — all against
/// `Preferences.trainingCalendar`, so "this week" matches the Progress tab and the widget.
/// Pure over `(store, preferences, now)`, which is what makes it testable without SwiftUI.
struct HomeSnapshot {
    var routine: RoutineInfo?
    /// False when no weekly plan exists yet — `routine` is then the first routine offered as a
    /// suggestion, not something the user scheduled, and the card should say so.
    var hasSchedule: Bool = true
    var nextSessionText: String?
    var streakCurrent: Int
    var streakLongest: Int
    var thisWeekCount: Int
    var recoveryMap: [Muscle: Double]
    var deloadSuggestion: DeloadSuggestionInfo?
    /// False when the store has no routines at all (deleted, or a corrupted seed) — Home shows
    /// the starter-plan empty state instead of a scheduled/rest-day card (OpenGym parity 52).
    var hasAnyRoutines: Bool = true
    /// Latest bodyweight reading, for Home's bodyweight tile (OpenGym parity 50).
    var bodyweightKg: Double?
    /// `bodyweightKg` minus the latest reading from 30 days before `now`; nil when there isn't
    /// one that far back to compare against.
    var bodyweightDeltaKg: Double?

    static let restDayHeadline = "Rest Day"

    /// The scheduled routine's name, or "Rest Day".
    var headline: String { routine?.name ?? Self.restDayHeadline }

    @MainActor
    static func make(store: WorkoutStore, preferences: Preferences, now: Date = Date()) -> HomeSnapshot {
        let calendar = preferences.trainingCalendar
        let weeklyGoal = preferences.weeklyGoal
        let streak = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: weeklyGoal, calendar: calendar, now: now
        )
        let latest = store.latestBodyMeasurement()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let past = latest.flatMap { _ in store.latestBodyMeasurement(asOf: thirtyDaysAgo) }
        let bodyweightDelta: Double? = {
            guard let latestKg = latest?.bodyweightKg, let pastKg = past?.bodyweightKg else { return nil }
            return latestKg - pastKg
        }()
        return HomeSnapshot(
            routine: store.todaysRoutine(calendar: calendar, now: now),
            hasSchedule: !store.schedule().days.isEmpty || !store.schedule().overrides.isEmpty,
            nextSessionText: nextSessionText(store.nextSession(calendar: calendar, now: now)),
            streakCurrent: streak.current,
            streakLongest: streak.longest,
            thisWeekCount: streak.thisWeekCount,
            // Same window and same calendar as the Recovery screen and the coach — Home used
            // to build its own 7-day slice, so one muscle read two different numbers on two
            // screens (and the Recovery screen's copy claimed a third window).
            recoveryMap: store.recoveryMap(now: now, calendar: calendar),
            deloadSuggestion: store.deloadSuggestion(
                snoozedUntil: preferences.deloadSnoozedUntil, weeklyGoal: weeklyGoal, now: now,
                calendar: calendar
            ),
            hasAnyRoutines: !store.routines().isEmpty,
            bodyweightKg: latest?.bodyweightKg,
            bodyweightDeltaKg: bodyweightDelta
        )
    }

    /// "Next: Pull B · Thursday" for the rest-day card; `nil` when nothing is scheduled.
    static func nextSessionText(_ next: (date: Date, routine: RoutineInfo)?) -> String? {
        guard let next else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "Next: \(next.routine.name) · \(formatter.string(from: next.date))"
    }
}
