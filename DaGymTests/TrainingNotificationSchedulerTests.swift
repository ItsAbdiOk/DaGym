import Foundation
import GymCore
import SwiftData
import Testing
import UserNotifications

@testable import DaGym

/// A fake `RestNotificationCenter` that just records calls — same shape
/// `RestNotificationSchedulerTests` uses, reused here since `TrainingNotificationScheduler`
/// reuses the same protocol.
private final class FakeNotificationCenter: RestNotificationCenter {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []

    func add(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }
}

@MainActor
@Suite("TrainingNotificationScheduler")
struct TrainingNotificationSchedulerTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A fixed Wednesday, so "Saturday hasn't happened yet this week" always holds regardless of
    /// what day the suite actually runs on.
    private var wednesday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        var components = DateComponents(year: 2026, month: 9, day: 9, hour: 12)
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? Date()
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    // MARK: - Streak reminder

    @Test("goal at risk and reachable: schedules the streak reminder for Saturday")
    func schedulesStreakReminderWhenAtRisk() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weeklyGoal = 1 // already reachable with zero workouts logged
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: calendar)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        let streakRequest = center.addedRequests.first { $0.identifier == "streak-reminder" }
        #expect(streakRequest != nil)
    }

    @Test("goal already met: does not schedule a streak reminder")
    func skipsStreakReminderWhenGoalMet() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weeklyGoal = 0 // 0 always counts as "met" (streakReminderDate returns nil)
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: calendar)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        let streakRequest = center.addedRequests.first { $0.identifier == "streak-reminder" }
        #expect(streakRequest == nil)
    }

    @Test("streak reminders disabled: no streak request even when the goal is at risk")
    func respectsStreakRemindersToggle() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weeklyGoal = 1
        preferences.streakRemindersEnabled = false
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: calendar)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        #expect(center.addedRequests.contains { $0.identifier == "streak-reminder" } == false)
    }

    // MARK: - Weekly recap

    @Test("weekly recap is scheduled for Sunday at the configured hour with a summary body")
    func schedulesWeeklyRecap() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.reminderHour = 18
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: calendar)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        let recapRequest = try #require(center.addedRequests.first { $0.identifier == "weekly-recap" })
        #expect(recapRequest.content.body.hasPrefix("This week: 0 workouts"))
        let trigger = try #require(recapRequest.trigger as? UNTimeIntervalNotificationTrigger)
        let fireDate = wednesday.addingTimeInterval(trigger.timeInterval)
        #expect(calendar.component(.weekday, from: fireDate) == 1)
        #expect(calendar.component(.hour, from: fireDate) == 18)
    }

    @Test("weekly recap disabled: no recap request")
    func respectsWeeklyRecapToggle() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weeklyRecapEnabled = false
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: calendar)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        #expect(center.addedRequests.contains { $0.identifier == "weekly-recap" } == false)
    }

    // MARK: - No duplicates

    @Test("rescheduling twice cancels both identifiers each time, never leaving duplicates")
    func reschedulingCancelsFirst() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weeklyGoal = 1
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: calendar)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)
        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        #expect(center.removedIdentifiers.count == 2)
        for identifiers in center.removedIdentifiers {
            #expect(Set(identifiers) == Set(["streak-reminder", "weekly-recap"]))
        }
    }

    // MARK: - recapBody formatting

    @Test("recapBody formats workouts, volume, PRs and the volume delta")
    func recapBodyFormatting() {
        let recap = WeeklyRecap(
            weekStart: Date(), weeklyGoal: 4, workouts: 3, sets: 54, volumeKg: 21_420, prs: 2,
            workoutsDelta: 1, setsDelta: 4, prsDelta: 2, volumeDeltaPercent: 12.7
        )
        let body = TrainingNotificationScheduler.recapBody(recap)
        #expect(body == "This week: 3 workouts · 21\u{2009}420 kg · 2 PRs (+13% vs last week)")
    }
}
