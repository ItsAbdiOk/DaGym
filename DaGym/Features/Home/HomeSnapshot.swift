import Foundation
import GymCore

/// Everything Home computes from the store in one pass: today's routine (or the rest-day
/// headline), streak, weekly count, recovery map and deload suggestion — all against
/// `Preferences.trainingCalendar`, so "this week" matches the Progress tab and the widget.
/// Pure over `(store, preferences, now)`, which is what makes it testable without SwiftUI.
struct HomeSnapshot {
    var routine: RoutineInfo?
    var nextSessionText: String?
    var streakCurrent: Int
    var streakLongest: Int
    var thisWeekCount: Int
    var recoveryMap: [Muscle: Double]
    var deloadSuggestion: DeloadSuggestionInfo?

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
        let since = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return HomeSnapshot(
            routine: store.todaysRoutine(calendar: calendar, now: now),
            nextSessionText: nextSessionText(store.nextSession(calendar: calendar, now: now)),
            streakCurrent: streak.current,
            streakLongest: streak.longest,
            thisWeekCount: streak.thisWeekCount,
            recoveryMap: Recovery.map(events: store.recoveryEvents(since: since), now: now),
            deloadSuggestion: store.deloadSuggestion(
                snoozedUntil: preferences.deloadSnoozedUntil,
                dismissedFingerprint: preferences.deloadDismissedFingerprint, weeklyGoal: weeklyGoal,
                calendar: calendar
            )
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
