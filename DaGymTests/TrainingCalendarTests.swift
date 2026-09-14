import Foundation
import GymCore
import SwiftData
import Testing
import UserNotifications

@testable import DaGym

/// X1/D11/S2/S16: "this week" used to mean `Calendar.current` in `Data/` and
/// `weekStartsMonday` in `Progress/`, so a Sunday session could land in different weeks on
/// adjacent screens. `Preferences.trainingCalendar` is the single fix — these tests prove a
/// Sunday session agrees across every consumer once it's threaded through.
@MainActor
@Suite("Training calendar")
struct TrainingCalendarTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The most recent (or today's) Sunday, computed from the actual device calendar so this
    /// test is deterministic without hard-coding a timezone-sensitive literal date.
    private var sunday: Date {
        let now = Date()
        let weekday = Calendar.current.component(.weekday, from: now) // 1 = Sunday
        return Calendar.current.date(byAdding: .day, value: -(weekday - 1), to: now) ?? now
    }

    /// The Wednesday of the same Sunday-starting week — a Monday-first calendar puts `sunday`
    /// in the *previous* week relative to this date, which is exactly the mismatch this batch
    /// fixes.
    private var wednesday: Date {
        Calendar.current.date(byAdding: .day, value: 3, to: sunday) ?? sunday
    }

    private var mondayFirstCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var sundayFirstCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        return calendar
    }

    private func logSundaySession(_ store: WorkoutStore) {
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        let routine = store.saveRoutine(id: nil, name: "Push A", exercises: [draft])
        let session = store.startBackfill(date: sunday, durationMinutes: 40, routineID: routine.id)
        session.exercises[0].sets[0].weightKg = 60
        session.exercises[0].sets[0].reps = 8
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
    }

    @Test("trainingCalendar's firstWeekday follows the preference, not the device locale")
    func trainingCalendarFollowsPreference() {
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weekStartsMonday = true
        #expect(preferences.trainingCalendar.firstWeekday == 2)
        preferences.weekStartsMonday = false
        #expect(preferences.trainingCalendar.firstWeekday == 1)
    }

    @Test("a Sunday session with weekStartsMonday = false counts as this week everywhere")
    func sundaySessionCountsThisWeekEverywhere() throws {
        let store = try makeStore()
        logSundaySession(store)

        // weekStartsMonday == false → `Preferences.trainingCalendar`'s firstWeekday is Sunday.
        let calendar = sundayFirstCalendar

        let streak = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: 1, calendar: calendar, now: wednesday
        )
        #expect(streak.thisWeekCount == 1)

        let state = store.milestoneState(weeklyGoal: 1, calendar: calendar)
        #expect(state.workoutCount == 1)

        let recap = store.weeklyRecap(for: wednesday, weeklyGoal: 1, calendar: calendar)
        #expect(recap.workouts == 1)

        let cells = store.consistencyCells(months: 1, now: wednesday, calendar: calendar)
        let sundayCell = cells.first { calendar.isDate($0.date, inSameDayAs: sunday) }
        #expect((sundayCell?.sets ?? 0) > 0)

        // Same data, same reference date — but a Monday-first calendar (the old
        // `Calendar.current` device-locale behaviour) puts the Sunday session in the
        // *previous* week, proving the mismatch this fix removes was real.
        let mismatched = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: 1, calendar: mondayFirstCalendar,
            now: wednesday
        )
        #expect(mismatched.thisWeekCount == 0)
    }

    @Test("the goal-at-risk reminder agrees: it doesn't fire once the Sunday session met the goal")
    func reminderAgreesWithTrainingCalendar() throws {
        let store = try makeStore()
        logSundaySession(store)

        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weekStartsMonday = false
        preferences.weeklyGoal = 1

        let center = FakeNotificationCenter()
        // No explicit `calendar:` override — production wiring: the scheduler reads
        // `preferences.trainingCalendar` itself on every call.
        let scheduler = TrainingNotificationScheduler(center: center)
        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        #expect(center.addedRequests.contains { $0.identifier == "streak-reminder" } == false)
    }

    private final class FakeNotificationCenter: RestNotificationCenter {
        private(set) var addedRequests: [UNNotificationRequest] = []
        func add(_ request: UNNotificationRequest) { addedRequests.append(request) }
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    }
}

/// Calendar-sync behaviour at the awkward edges of the calendar: month and year boundaries, a
/// Sunday-first week, a timezone well away from UTC, and a DST changeover. The rest of the sync
/// suite pins everything to one Monday in UTC, where none of these can go wrong.
@Suite("Calendar sync boundaries")
struct CalendarSyncBoundaryTests {
    private static func calendar(timeZone: String = "UTC", firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static func date(
        _ year: Int, _ month: Int, _ day: Int, calendar: Calendar = calendar()
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date()
    }

    private func routine(name: String) -> RoutineInfo {
        RoutineInfo(
            name: name, exercises: [], setCount: 0, estimatedMinutes: 50, progressionRule: "linear",
            progressionDetail: ""
        )
    }

    private func request(
        schedule: WeeklySchedule, routines: [RoutineInfo], startDate: Date, days: Int = 7,
        calendar: Calendar = CalendarSyncBoundaryTests.calendar()
    ) -> ScheduleSyncRequest {
        ScheduleSyncRequest(
            schedule: schedule, routines: routines, startDate: startDate, days: days,
            defaultStartHour: 18, existingEventIDs: [:], calendar: calendar
        )
    }

    @Test("a window spanning a month boundary plans every day on both sides")
    func monthBoundary() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        for weekday in Weekday.allCases { schedule.setRoutines([pushA.id], on: weekday) }
        let calendar = Self.calendar()
        let lateJanuary = Self.date(2026, 1, 29)

        let result = try await service.sync(request(
            schedule: schedule, routines: [pushA], startDate: lateJanuary, days: 5
        ))

        #expect(result.count == 5)
        let februaryFirst = CalendarSyncService.eventKey(
            date: Self.date(2026, 2, 1), routineID: pushA.id, calendar: calendar
        )
        #expect(result[februaryFirst] != nil)
        #expect(result.keys.contains { $0.hasPrefix("2026-02-02") })
    }

    @Test("a window spanning a year boundary plans every day on both sides")
    func yearBoundary() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        for weekday in Weekday.allCases { schedule.setRoutines([pushA.id], on: weekday) }

        let result = try await service.sync(request(
            schedule: schedule, routines: [pushA], startDate: Self.date(2025, 12, 30), days: 4
        ))

        #expect(result.count == 4)
        #expect(result.keys.contains { $0.hasPrefix("2025-12-31") })
        #expect(result.keys.contains { $0.hasPrefix("2026-01-01") })
    }

    /// The sync is day-based, so a Sunday-first calendar must produce exactly the same events —
    /// what changes is only which weekday the lifter *sees* first in the schedule list.
    @Test("a Sunday-first calendar plans the same weekdays as a Monday-first one")
    func sundayFirstWeek() async throws {
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.sunday] = pushA.id
        schedule.days[.wednesday] = pushA.id

        var results: [Set<String>] = []
        for firstWeekday in [1, 2] {
            let fake = FakeEventStore()
            let service = CalendarSyncService(eventStore: fake)
            let calendar = Self.calendar(firstWeekday: firstWeekday)
            let result = try await service.sync(request(
                schedule: schedule, routines: [pushA],
                startDate: Self.date(2026, 1, 5, calendar: calendar), calendar: calendar
            ))
            results.append(Set(result.keys))
        }
        #expect(results[0] == results[1])
        #expect(results[0].count == 2)
        #expect(results[0].contains { $0.hasPrefix("2026-01-07") }, "Wednesday")
        #expect(results[0].contains { $0.hasPrefix("2026-01-11") }, "Sunday")
    }

    /// In `Europe/London`, 2026-03-29 is the spring-forward day: 01:00 jumps to 02:00, so that
    /// calendar day is 23 hours long. Day-keyed planning must not skip or double it, and an
    /// 18:00 session must still start at 18:00 local time.
    @Test("a DST changeover doesn't skip, duplicate or shift a day")
    func dstChangeover() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let calendar = Self.calendar(timeZone: "Europe/London")
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        for weekday in Weekday.allCases { schedule.setRoutines([pushA.id], on: weekday) }

        let result = try await service.sync(request(
            schedule: schedule, routines: [pushA],
            startDate: Self.date(2026, 3, 27, calendar: calendar), days: 4, calendar: calendar
        ))

        #expect(result.count == 4)
        for day in 27...30 {
            #expect(
                result.keys.contains { $0.hasPrefix(String(format: "2026-03-%02d", day)) },
                "2026-03-\(day) must be planned exactly once"
            )
        }
        let springForward = CalendarSyncService.eventKey(
            date: Self.date(2026, 3, 29, calendar: calendar), routineID: pushA.id, calendar: calendar
        )
        let eventID = try #require(result[springForward])
        let event = try #require(fake.events[eventID])
        #expect(calendar.component(.hour, from: event.start) == 18)
    }

    /// Same wall-clock plan, a timezone well west of UTC: the event still lands at 18:00 local,
    /// and the day keys still line up with the lifter's own calendar days.
    @Test("a non-UTC timezone keys days and start times by local time")
    func nonUTCTimezone() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let calendar = Self.calendar(timeZone: "America/Los_Angeles")
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        let monday = Self.date(2026, 1, 5, calendar: calendar)

        let result = try await service.sync(request(
            schedule: schedule, routines: [pushA], startDate: monday, calendar: calendar
        ))

        let key = CalendarSyncService.eventKey(date: monday, routineID: pushA.id, calendar: calendar)
        let eventID = try #require(result[key])
        let event = try #require(fake.events[eventID])
        #expect(calendar.component(.hour, from: event.start) == 18)
        #expect(calendar.component(.day, from: event.start) == 5)
    }
}
