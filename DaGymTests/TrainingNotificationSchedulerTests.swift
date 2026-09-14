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

    @Test("goal at risk and reachable: schedules the streak reminder for Saturday at the configured hour")
    func schedulesStreakReminderWhenAtRisk() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.streakRemindersEnabled = true
        preferences.weeklyGoal = 1 // already reachable with zero workouts logged
        preferences.reminderHour = 19
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: calendar)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        let streakRequest = try #require(center.addedRequests.first { $0.identifier == "streak-reminder" })
        let trigger = try #require(streakRequest.trigger as? UNTimeIntervalNotificationTrigger)
        let fireDate = wednesday.addingTimeInterval(trigger.timeInterval)
        #expect(fireDate > wednesday)
        #expect(calendar.component(.weekday, from: fireDate) == 7) // Saturday
        #expect(calendar.component(.hour, from: fireDate) == 19)
        #expect(streakRequest.content.body.contains("1 more"))
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
        preferences.weeklyRecapEnabled = true
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

    /// Finding 6: the recap body is frozen at schedule time, but a one-shot scheduled *after*
    /// Sunday's hour has passed fires a whole week later — so a lifter who finished on Sunday
    /// evening and then trained nothing all week got "This week: 3 workouts" for a week with none.
    /// When the fire date isn't in the week the numbers describe, the body stops claiming numbers.
    @Test("a recap landing next week carries no frozen counts")
    func recapForALaterWeekDropsTheNumbers() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weeklyRecapEnabled = true
        preferences.reminderHour = 18
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: calendar)
        // Sunday 2026-09-13 at 19:00: this week's 18:00 recap has already gone.
        let sundayEvening = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 19))
        )

        scheduler.rescheduleAll(store: store, preferences: preferences, now: sundayEvening)

        let recap = try #require(center.addedRequests.first { $0.identifier == "weekly-recap" })
        #expect(recap.content.body == TrainingNotificationScheduler.pendingRecapBody)
        #expect(!recap.content.body.contains("This week:"))
        let trigger = try #require(recap.trigger as? UNTimeIntervalNotificationTrigger)
        let fireDate = sundayEvening.addingTimeInterval(trigger.timeInterval)
        #expect(calendar.component(.weekday, from: fireDate) == 1)
        #expect(!calendar.isDate(fireDate, equalTo: sundayEvening, toGranularity: .weekOfYear))
    }

    /// The Sunday-start twin of the guard above. With `firstWeekday == 1` Sunday *opens* a week,
    /// so the coming Sunday's recap is for the Sun–Sat week that is under way now — comparing the
    /// fire date's week to `now`'s week said "different week" every day but Sunday, and
    /// Sunday-start lifters never got numbers at all.
    @Test("Sunday-start calendar: a mid-week reschedule still carries this week's numbers")
    func sundayStartRecapCarriesThisWeeksNumbers() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        let routineID = store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
        var sundayStart = calendar
        sundayStart.firstWeekday = 1
        // Monday 2026-09-07 at 12:00 (UTC): the week that started on Sunday the 6th.
        let monday = try #require(
            sundayStart.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))
        )
        let session = store.startBackfill(date: monday, durationMinutes: 40, routineID: routineID)
        session.exercises[0].sets[0].weightKg = 60
        session.exercises[0].sets[0].reps = 8
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weeklyRecapEnabled = true
        preferences.reminderHour = 18
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: sundayStart)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: monday.addingTimeInterval(3_600))

        let recap = try #require(center.addedRequests.first { $0.identifier == "weekly-recap" })
        #expect(recap.content.body.hasPrefix("This week: 1 workout"))
        let trigger = try #require(recap.trigger as? UNTimeIntervalNotificationTrigger)
        let fireDate = monday.addingTimeInterval(3_600 + trigger.timeInterval)
        #expect(sundayStart.component(.weekday, from: fireDate) == 1)
        #expect(sundayStart.component(.day, from: fireDate) == 13)
    }

    /// Sunday evening on a Sunday-start calendar: the next recap fires in seven days but closes
    /// the week that began this morning, so what it reports is this week — numbers are honest.
    @Test("Sunday-start calendar: a Sunday-evening reschedule describes the week just begun")
    func sundayStartRecapOnSundayEveningDescribesTheNewWeek() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weeklyRecapEnabled = true
        preferences.reminderHour = 18
        var sundayStart = calendar
        sundayStart.firstWeekday = 1
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center, calendar: sundayStart)
        // Sunday 2026-09-13 at 19:00: today's recap has gone; the next one closes the week that
        // only started today.
        let sundayEvening = try #require(
            sundayStart.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 19))
        )

        scheduler.rescheduleAll(store: store, preferences: preferences, now: sundayEvening)

        let recap = try #require(center.addedRequests.first { $0.identifier == "weekly-recap" })
        #expect(recap.content.body.hasPrefix("This week: 0 workouts"))
        let trigger = try #require(recap.trigger as? UNTimeIntervalNotificationTrigger)
        let fireDate = sundayEvening.addingTimeInterval(trigger.timeInterval)
        #expect(sundayStart.component(.day, from: fireDate) == 20)
    }

    // MARK: - No duplicates

    @Test("rescheduling twice cancels both identifiers each time, never leaving duplicates")
    func reschedulingCancelsFirst() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.streakRemindersEnabled = true
        preferences.weeklyRecapEnabled = true
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
