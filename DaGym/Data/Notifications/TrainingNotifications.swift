import Foundation
import GymCore
import UserNotifications

/// Schedules the two training-consistency notifications (plan.md §6.4): a Saturday-evening
/// "goal at risk" streak reminder, and a Sunday-evening weekly recap. Reuses
/// `RestNotificationCenter` (Features/LiveActivity/RestNotificationScheduler.swift) — same
/// add/cancel shape, so a second fake-able protocol would just be duplication.
@MainActor
final class TrainingNotificationScheduler {
    private static let streakIdentifier = "streak-reminder"
    private static let recapIdentifier = "weekly-recap"

    private let center: RestNotificationCenter
    /// Explicit override for tests; nil in production so every call reads
    /// `preferences.trainingCalendar` fresh — the goal-at-risk and recap notifications must
    /// agree with whatever week the user's `weekStartsMonday` preference currently defines, not
    /// whatever the device locale said the moment this scheduler was constructed.
    private let calendarOverride: Calendar?
    /// The "workout day" reminder (features #3) lives in its own type/identifier space but is
    /// rescheduled from the same hooks as the streak/recap notifications below. Defaults to its
    /// own real notification center, independent of `center`, so tests that fake `center` for the
    /// streak/recap assertions aren't also asked to account for workout-day-reminder calls.
    private let workoutDayReminderScheduler: WorkoutDayReminderScheduler

    init(
        center: RestNotificationCenter = UNUserNotificationCenter.current(), calendar: Calendar? = nil,
        workoutDayReminderScheduler: WorkoutDayReminderScheduler? = nil
    ) {
        self.center = center
        self.calendarOverride = calendar
        self.workoutDayReminderScheduler = workoutDayReminderScheduler ?? WorkoutDayReminderScheduler()
    }

    private func calendar(for preferences: Preferences) -> Calendar {
        calendarOverride ?? preferences.trainingCalendar
    }

    /// Cancels both of our identifiers, then reschedules whichever are enabled in `preferences`.
    /// Cancel-then-add means calling this repeatedly (every finished workout, every launch) never
    /// leaves a stale or duplicate notification pending.
    func rescheduleAll(store: WorkoutStore, preferences: Preferences, now: Date = Date()) {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.streakIdentifier, Self.recapIdentifier]
        )
        if preferences.streakRemindersEnabled {
            scheduleStreakReminder(store: store, preferences: preferences, now: now)
        }
        if preferences.weeklyRecapEnabled {
            scheduleWeeklyRecap(store: store, preferences: preferences, now: now)
        }
        workoutDayReminderScheduler.rescheduleAll(
            store: store, preferences: preferences, calendar: calendar(for: preferences)
        )
    }

    /// Registers this scheduler on `store` so a reschedule happens after every finished workout,
    /// plus one reschedule right now — call once at launch (`DaGymApp`). Captures `self` strongly:
    /// nothing else keeps a scheduler created just for this call alive, and it never stores a
    /// reference back to `store`, so this can't form a retain cycle — it just ties the
    /// scheduler's lifetime to the store's, which is what we want.
    func bind(store: WorkoutStore, preferences: Preferences) {
        rescheduleAll(store: store, preferences: preferences)
        store.workoutFinishedObservers.append { _ in
            self.rescheduleAll(store: store, preferences: preferences)
        }
    }

    private func scheduleStreakReminder(store: WorkoutStore, preferences: Preferences, now: Date) {
        let calendar = calendar(for: preferences)
        let streak = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: preferences.weeklyGoal,
            calendar: calendar, now: now
        )
        guard let fireDate = ConsistencyCalendar.streakReminderDate(
            now: now, weeklyGoal: preferences.weeklyGoal, thisWeekCount: streak.thisWeekCount,
            calendar: calendar, hour: preferences.reminderHour
        ), fireDate > now else { return }

        let remaining = preferences.weeklyGoal - streak.thisWeekCount
        let content = UNMutableNotificationContent()
        content.title = "Goal at risk"
        content.body = "\(remaining) more \(remaining == 1 ? "session" : "sessions") to hit your weekly goal."
        content.sound = .default
        add(content: content, identifier: Self.streakIdentifier, fireDate: fireDate, now: now)
    }

    private func scheduleWeeklyRecap(store: WorkoutStore, preferences: Preferences, now: Date) {
        let calendar = calendar(for: preferences)
        guard let fireDate = Self.nextSundayEvening(
            after: now, hour: preferences.reminderHour, calendar: calendar
        ) else { return }
        let recap = store.weeklyRecap(for: now, weeklyGoal: preferences.weeklyGoal, calendar: calendar)
        let content = UNMutableNotificationContent()
        content.title = "Weekly recap"
        content.body = Self.recapBody(recap, unit: preferences.weightUnit)
        content.sound = .default
        add(content: content, identifier: Self.recapIdentifier, fireDate: fireDate, now: now)
    }

    private func add(
        content: UNMutableNotificationContent, identifier: String, fireDate: Date, now: Date
    ) {
        // Interval is measured from the injected `now` so scheduling is deterministic in tests.
        let interval = max(0.1, fireDate.timeIntervalSince(now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// The next Sunday at `hour:00` strictly after `now` — this week's if it hasn't happened yet,
    /// otherwise next week's.
    static func nextSundayEvening(after now: Date, hour: Int, calendar: Calendar) -> Date? {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now),
              let sunday = weekday(1, in: weekInterval, calendar: calendar) else { return nil }
        if let candidate = atHour(hour, on: sunday, calendar: calendar), candidate > now {
            return candidate
        }
        guard let nextSunday = calendar.date(byAdding: .weekOfYear, value: 1, to: sunday) else { return nil }
        return atHour(hour, on: nextSunday, calendar: calendar)
    }

    /// Walks the 7 days of `interval` for the one whose Gregorian weekday matches (1 = Sunday).
    private static func weekday(_ target: Int, in interval: DateInterval, calendar: Calendar) -> Date? {
        var cursor = interval.start
        for _ in 0..<7 {
            if calendar.component(.weekday, from: cursor) == target { return cursor }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    private static func atHour(_ hour: Int, on day: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    /// "This week: 3 workouts · 21 420 kg · 2 PRs (+12% vs last week)" — in the user's display
    /// unit (X2: a weight string built below the UI layer must still take `unit:`, not assume kg).
    static func recapBody(_ recap: WeeklyRecap, unit: WeightUnit = .kg) -> String {
        let workoutsPart = "\(recap.workouts) \(recap.workouts == 1 ? "workout" : "workouts")"
        let prsPart = "\(recap.prs) \(recap.prs == 1 ? "PR" : "PRs")"
        let volumePart = "\(formattedVolume(recap.volumeKg, unit: unit)) \(unit.symbol)"
        var line = "\(workoutsPart) · \(volumePart) · \(prsPart)"
        if let percent = recap.volumeDeltaPercent {
            let sign = percent >= 0 ? "+" : ""
            line += " (\(sign)\(Int(percent.rounded()))% vs last week)"
        }
        return "This week: \(line)"
    }

    private static func formattedVolume(_ kg: Double, unit: WeightUnit) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: unit.display(kg: kg))) ?? "\(Int(unit.display(kg: kg)))"
    }
}
