import Foundation
import GymCore
import UserNotifications

/// Schedules a repeating "workout day" local notification for every weekday the user has a
/// routine planned on (`WorkoutStore.schedule().days`), firing at `preferences.
/// workoutDayReminderHour` (OpenGym parity, features "Adopt now" #3). One
/// `UNCalendarNotificationTrigger` per scheduled weekday, `repeats: true`, so a single reschedule
/// keeps firing week after week until the schedule or the hour changes.
///
/// Owned by `TrainingNotificationScheduler`, which calls `rescheduleAll` from the same places it
/// reschedules the streak/recap notifications — `DaGymApp` needs no separate wiring.
@MainActor
final class WorkoutDayReminderScheduler {
    private static let identifierPrefix = "workout-day-reminder-"
    private static var allIdentifiers: [String] { Weekday.allCases.map { identifier(for: $0) } }

    private let center: RestNotificationCenter

    init(center: RestNotificationCenter = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Cancels every previously scheduled workout-day reminder, then — if the toggle is on —
    /// schedules one per weekday the current schedule plans a routine for. Cancel-then-add keeps
    /// this idempotent: dropping a scheduled day, or turning the toggle off, always removes the
    /// stale request instead of leaving it pending.
    func rescheduleAll(store: WorkoutStore, preferences: Preferences, calendar: Calendar) {
        center.removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers)
        guard preferences.workoutDayReminderEnabled else { return }
        let scheduledDays = store.schedule().days.keys
        for weekday in scheduledDays {
            schedule(weekday: weekday, hour: preferences.workoutDayReminderHour, calendar: calendar)
        }
    }

    private func schedule(weekday: Weekday, hour: Int, calendar: Calendar) {
        var components = DateComponents()
        components.calendar = calendar
        components.weekday = weekday.rawValue
        components.hour = hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Workout day"
        content.body = "Today's a scheduled training day."
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: Self.identifier(for: weekday), content: content, trigger: trigger
        ))
    }

    private static func identifier(for weekday: Weekday) -> String {
        identifierPrefix + String(weekday.rawValue)
    }
}
