import Foundation
import GymCore
import UserNotifications

/// Schedules a "workout day" local notification for each upcoming day the user actually has a
/// routine planned on (OpenGym parity, features "Adopt now" #3), firing at
/// `preferences.workoutDayReminderHour`.
///
/// One dated `UNCalendarNotificationTrigger` per planned day rather than one repeating trigger per
/// weekday. `WeeklySchedule` is not just a weekday map — `dateOverrides` move a single session, so
/// a Wednesday session dragged to Saturday used to still buzz on Wednesday and stay silent on
/// Saturday. Asking the schedule what it plans *on each date* is the only version of this that
/// agrees with what the lifter sees in the schedule editor.
///
/// The trade for losing `repeats: true` is a horizon: `horizonDays` of reminders at a time. That
/// is fine because every path that can change the answer reschedules — launch, a finished workout,
/// a schedule edit, a session moved in History, and the Settings toggles — and a lifter who hasn't
/// opened DaGym in four weeks is not being nudged back by a "workout day" ping.
///
/// Owned by `TrainingNotificationScheduler`, which calls `rescheduleAll` from all of those places.
@MainActor
final class WorkoutDayReminderScheduler {
    static let horizonDays = 28
    private static let identifierPrefix = "workout-day-reminder-"

    /// Every identifier this scheduler can ever have used: today's horizon slots, plus the seven
    /// weekday-numbered identifiers the old repeating version wrote, so an app updating from that
    /// build doesn't keep firing them forever.
    private static var allIdentifiers: [String] {
        let slots = (0..<horizonDays).map { identifier(slot: $0) }
        let legacy = Weekday.allCases.map { identifierPrefix + String($0.rawValue) }
        return Array(Set(slots + legacy)).sorted()
    }

    private let center: RestNotificationCenter

    init(center: RestNotificationCenter = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Cancels every previously scheduled workout-day reminder, then — if the toggle is on —
    /// schedules one per planned day inside the horizon. Cancel-then-add keeps this idempotent:
    /// dropping a day, moving a session, or turning the toggle off always removes the stale
    /// request instead of leaving it pending.
    func rescheduleAll(
        store: WorkoutStore, preferences: Preferences, calendar: Calendar, now: Date = Date()
    ) {
        center.removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers)
        guard preferences.workoutDayReminderEnabled else { return }
        let schedule = store.schedule()
        let routines = store.routines()
        let hour = preferences.workoutDayReminderHour
        let startOfToday = calendar.startOfDay(for: now)
        var slot = 0
        for offset in 0..<Self.horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let fireDate = Self.atHour(hour, on: day, calendar: calendar), fireDate > now
            else { continue }
            let planned = schedule.routineIDs(on: day, calendar: calendar)
                .compactMap { id in routines.first { $0.id == id } }
            guard !planned.isEmpty else { continue }
            add(
                slot: slot, fireDate: fireDate, calendar: calendar,
                name: RoutineInfo.joinedNames(planned)
            )
            slot += 1
        }
    }

    private func add(slot: Int, fireDate: Date, calendar: Calendar, name: String) {
        // `.weekday` alongside the date is redundant for matching but makes the request
        // self-describing (and is what the tests read).
        var components = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute], from: fireDate
        )
        components.calendar = calendar
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Workout day"
        content.body = name.isEmpty ? "Today's a scheduled training day." : "\(name) is on today."
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: Self.identifier(slot: slot), content: content, trigger: trigger
        ))
    }

    private static func atHour(_ hour: Int, on day: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    private static func identifier(slot: Int) -> String {
        identifierPrefix + "slot-" + String(slot)
    }
}
