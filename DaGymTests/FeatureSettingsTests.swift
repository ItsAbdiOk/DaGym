import Foundation
import GymCore
import SwiftData
import Testing
import UserNotifications

@testable import DaGym

/// A fake `RestNotificationCenter` that just records calls — same shape every scheduler test
/// file uses (`RestNotificationSchedulerTests`, `TrainingNotificationSchedulerTests`).
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
private func makeStore() throws -> WorkoutStore {
    let container = try ModelContainer.dagym(inMemory: true)
    return WorkoutStore(context: ModelContext(container))
}

// MARK: - WorkoutDayReminderScheduler (Batch B3 item 3)

@MainActor
@Suite("WorkoutDayReminderScheduler")
struct WorkoutDayReminderSchedulerTests {
    @Test("schedules one repeating calendar trigger per scheduled weekday, at the configured hour")
    func schedulesPerScheduledWeekday() throws {
        let store = try makeStore()
        store.saveSchedule(WeeklySchedule(days: [.monday: UUID(), .thursday: UUID()]))
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = true
        preferences.workoutDayReminderHour = 7
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)

        scheduler.rescheduleAll(store: store, preferences: preferences, calendar: .current)

        #expect(center.addedRequests.count == 2)
        for request in center.addedRequests {
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.repeats)
            #expect(trigger.dateComponents.hour == 7)
        }
        let weekdays = Set(center.addedRequests.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday
        })
        #expect(weekdays == Set([Weekday.monday.rawValue, Weekday.thursday.rawValue]))
    }

    @Test("disabled: cancels every identifier and schedules nothing")
    func disabledSchedulesNothing() throws {
        let store = try makeStore()
        store.saveSchedule(WeeklySchedule(days: [.monday: UUID()]))
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = false
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)

        scheduler.rescheduleAll(store: store, preferences: preferences, calendar: .current)

        #expect(center.addedRequests.isEmpty)
        #expect(center.removedIdentifiers.count == 1)
    }

    @Test("rescheduling twice never leaves duplicate requests: each call cancels every identifier first")
    func reschedulingCancelsFirst() throws {
        let store = try makeStore()
        store.saveSchedule(WeeklySchedule(days: [.monday: UUID(), .friday: UUID()]))
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = true
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)

        scheduler.rescheduleAll(store: store, preferences: preferences, calendar: .current)
        scheduler.rescheduleAll(store: store, preferences: preferences, calendar: .current)

        #expect(center.removedIdentifiers.count == 2)
        #expect(Set(center.removedIdentifiers[1]).count == Weekday.allCases.count)
    }

    @Test("changing the schedule after enabling: the next reschedule reflects the new days only")
    func reflectsScheduleChanges() throws {
        let store = try makeStore()
        store.saveSchedule(WeeklySchedule(days: [.monday: UUID()]))
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = true
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)
        scheduler.rescheduleAll(store: store, preferences: preferences, calendar: .current)

        store.saveSchedule(WeeklySchedule(days: [.wednesday: UUID()]))
        scheduler.rescheduleAll(store: store, preferences: preferences, calendar: .current)

        let lastWeekdays = center.addedRequests.suffix(1).compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday
        }
        #expect(lastWeekdays == [Weekday.wednesday.rawValue])
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

// MARK: - TrainingNotificationScheduler integration (Batch B3 item 3)

@MainActor
@Suite("TrainingNotificationScheduler + workout-day reminder")
struct TrainingNotificationWorkoutDayTests {
    @Test("rescheduleAll also reschedules the workout-day reminder through the injected scheduler")
    func rescheduleAllIncludesWorkoutDayReminder() throws {
        let store = try makeStore()
        store.saveSchedule(WeeklySchedule(days: [.tuesday: UUID()]))
        let defaults = UserDefaults(suiteName: #function) ?? .standard
        defaults.removePersistentDomain(forName: #function)
        let preferences = Preferences(suite: defaults)
        preferences.workoutDayReminderEnabled = true
        preferences.workoutDayReminderHour = 9

        let workoutDayCenter = FakeNotificationCenter()
        let workoutDayScheduler = WorkoutDayReminderScheduler(center: workoutDayCenter)
        let scheduler = TrainingNotificationScheduler(
            center: FakeNotificationCenter(), calendar: .current,
            workoutDayReminderScheduler: workoutDayScheduler
        )

        scheduler.rescheduleAll(store: store, preferences: preferences)

        #expect(workoutDayCenter.addedRequests.count == 1)
        let addedTrigger = workoutDayCenter.addedRequests.first?.trigger
        let trigger = try #require(addedTrigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.weekday == Weekday.tuesday.rawValue)
        #expect(trigger.dateComponents.hour == 9)
    }
}

// MARK: - WorkoutStore.wipeAllData (Batch B3 item 26)

@MainActor
@Suite("WorkoutStore.wipeAllData")
struct WorkoutStoreWipeAllDataTests {
    @Test("deletes every model and resets preferences to their shipped defaults")
    func wipesEverythingAndResetsPreferences() throws {
        let store = try makeStore()
        store.context.insert(ExerciseModel(name: "Bench Press", isCustom: true))
        store.saveSchedule(WeeklySchedule(days: [.monday: UUID()]))
        store.save()
        #expect(!((try? store.context.fetch(FetchDescriptor<ExerciseModel>())) ?? []).isEmpty)
        #expect(!((try? store.context.fetch(FetchDescriptor<ScheduleModel>())) ?? []).isEmpty)

        let defaults = UserDefaults(suiteName: #function) ?? .standard
        defaults.removePersistentDomain(forName: #function)
        let preferences = Preferences(suite: defaults)
        preferences.weeklyGoal = 6
        preferences.effortTrackingEnabled = false
        preferences.appearance = .dark
        preferences.bodyFigure = .male
        preferences.weighInBeforeWorkout = true
        preferences.workoutDayReminderEnabled = true

        store.wipeAllData(preferences: preferences)

        #expect(((try? store.context.fetch(FetchDescriptor<ExerciseModel>())) ?? []).isEmpty)
        #expect(((try? store.context.fetch(FetchDescriptor<ScheduleModel>())) ?? []).isEmpty)
        #expect(preferences.weeklyGoal == 4)
        #expect(preferences.effortTrackingEnabled)
        #expect(preferences.appearance == .system)
        #expect(preferences.bodyFigure == .neutral)
        #expect(preferences.weighInBeforeWorkout == false)
        #expect(preferences.workoutDayReminderEnabled == false)
    }

    /// Guards `WorkoutStore.wipeAllData`'s explicit, unrolled delete list: if a model is ever
    /// added to `DaGymSchema.mainModels` without a matching `context.delete(model:)` line, this
    /// fails instead of silently leaving that model's rows behind after a reset.
    @Test("mainModels count matches the number of types wipeAllData deletes")
    func mainModelsCountMatchesDeleteList() {
        #expect(DaGymSchema.mainModels.count == 18)
    }
}
