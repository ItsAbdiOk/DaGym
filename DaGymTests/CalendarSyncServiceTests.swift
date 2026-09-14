import Foundation
import GymCore
import Testing

@testable import DaGym

/// One recorded event, keyed by id in `FakeEventStore.events`.
private struct StoredEvent {
    var title: String
    var start: Date
    var end: Date
    var notes: String
    var url: URL?
}

/// Records every call so tests can assert on it without touching EventKit.
private final class FakeEventStore: EventStoring, @unchecked Sendable {
    var accessGranted = true
    private var storedCalendars: [CalendarInfo] = []
    private(set) var events: [String: StoredEvent] = [:]
    private(set) var deletedIDs: [String] = []
    private(set) var createCalendarCount = 0
    private var nextEventNumber = 0

    func requestWriteOnlyAccess() async throws -> Bool { accessGranted }

    func calendars() -> [CalendarInfo] { storedCalendars }

    func createCalendar(named name: String) throws -> String {
        createCalendarCount += 1
        let calendar = CalendarInfo(id: "cal-\(createCalendarCount)", title: name)
        storedCalendars.append(calendar)
        return calendar.id
    }

    func upsertEvent(id: String?, draft: EventDraft, calendarID: String) throws -> String {
        let eventID = id ?? {
            nextEventNumber += 1
            return "event-\(nextEventNumber)"
        }()
        events[eventID] = StoredEvent(
            title: draft.title, start: draft.start, end: draft.end, notes: draft.notes, url: draft.url
        )
        return eventID
    }

    func deleteEvent(id: String) throws {
        deletedIDs.append(id)
        events.removeValue(forKey: id)
    }

    func fetchEvents(inCalendar calendarID: String, from: Date, to: Date) throws -> [String] {
        Array(events.keys)
    }
}

@Suite("Calendar sync")
struct CalendarSyncServiceTests {
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Monday 2026-01-05.
    private static func monday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        return calendar().date(from: components) ?? Date()
    }

    private func routine(name: String, exerciseNames: [String] = []) -> RoutineInfo {
        let exercises = exerciseNames.map { exerciseName in
            ExerciseInfo(id: UUID(), name: exerciseName, primary: [], secondary: [], equipment: "barbell")
        }
        return RoutineInfo(
            name: name, exercises: exercises, setCount: 0, estimatedMinutes: 50, progressionRule: "linear",
            progressionDetail: ""
        )
    }

    private func request(
        schedule: WeeklySchedule, routines: [RoutineInfo], existingEventIDs: [String: String] = [:]
    ) -> ScheduleSyncRequest {
        ScheduleSyncRequest(
            schedule: schedule, routines: routines, startDate: Self.monday(), days: 7, defaultStartHour: 18,
            existingEventIDs: existingEventIDs, calendar: Self.calendar()
        )
    }

    @Test("first sync creates one event per planned session, with its notes and deep link")
    func firstSyncCreatesEvents() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A", exerciseNames: ["Bench Press", "Overhead Press"])
        let legs = routine(name: "Legs")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        schedule.days[.wednesday] = legs.id

        let eventIDs = try await service.sync(request(schedule: schedule, routines: [pushA, legs]))

        #expect(eventIDs.count == 2)
        #expect(fake.events.count == 2)
        #expect(fake.createCalendarCount == 1)

        // The notes and deep-link URL `RootView.handleOpenURL` relies on to start the right
        // routine from a calendar tap — dropped by a fake that only kept title/start/end.
        let mondayKey = CalendarSyncService.eventKey(
            date: Self.monday(), routineID: pushA.id, calendar: Self.calendar()
        )
        let pushAEventID = try #require(eventIDs[mondayKey])
        let pushAEvent = try #require(fake.events[pushAEventID])
        #expect(pushAEvent.notes == "Bench Press\nOverhead Press")
        #expect(pushAEvent.url == URL(string: "dagym://start?routine=\(pushA.id.uuidString)"))
    }

    @Test("re-syncing an unchanged schedule creates no new events")
    func resyncCreatesNone() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id

        let first = try await service.sync(request(schedule: schedule, routines: [pushA]))
        let second = try await service.sync(
            request(schedule: schedule, routines: [pushA], existingEventIDs: first)
        )

        #expect(second == first)
        #expect(fake.events.count == 1)
        #expect(fake.deletedIDs.isEmpty)
    }

    @Test("moving a session deletes the old date's event and creates one on the new date")
    func movingSessionRelocatesEvent() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        let monday = Self.monday()
        let thursday = Self.calendar().date(byAdding: .day, value: 3, to: monday) ?? monday
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id

        let first = try await service.sync(request(schedule: schedule, routines: [pushA]))
        let mondayKey = CalendarSyncService.eventKey(
            date: monday, routineID: pushA.id, calendar: Self.calendar()
        )
        let thursdayKey = CalendarSyncService.eventKey(
            date: thursday, routineID: pushA.id, calendar: Self.calendar()
        )
        let originalEventID = try #require(first[mondayKey])

        schedule.moved(date: monday, to: nil, calendar: Self.calendar())
        schedule.moved(date: thursday, to: pushA.id, calendar: Self.calendar())

        let second = try await service.sync(
            request(schedule: schedule, routines: [pushA], existingEventIDs: first)
        )

        #expect(fake.deletedIDs == [originalEventID])
        #expect(second[thursdayKey] != nil)
        #expect(second[mondayKey] == nil)
    }

    @Test("clearing a scheduled day deletes its event")
    func removingDayDeletesEvent() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id

        let first = try await service.sync(request(schedule: schedule, routines: [pushA]))

        schedule.days[.monday] = nil
        let second = try await service.sync(
            request(schedule: schedule, routines: [pushA], existingEventIDs: first)
        )

        #expect(second.isEmpty)
        #expect(fake.events.isEmpty)
        #expect(fake.deletedIDs.count == 1)
    }

    @Test("a day with two routines produces two events, and re-syncing is idempotent")
    func multiRoutineDayCreatesOneEventPerRoutine() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        let arms = routine(name: "Arms")
        var schedule = WeeklySchedule()
        schedule.addRoutine(pushA.id, to: .monday)
        schedule.addRoutine(arms.id, to: .monday)

        let first = try await service.sync(request(schedule: schedule, routines: [pushA, arms]))
        #expect(first.count == 2)
        #expect(fake.events.count == 2)
        #expect(Set(fake.events.values.map(\.title)) == ["DaGym · Push A", "DaGym · Arms"])

        // Re-syncing the same schedule must not create or delete anything.
        let second = try await service.sync(
            request(schedule: schedule, routines: [pushA, arms], existingEventIDs: first)
        )
        #expect(second == first)
        #expect(fake.events.count == 2)
        #expect(fake.deletedIDs.isEmpty)
    }

    @Test("removing one routine from a multi-routine day deletes exactly its event")
    func removingOneRoutineFromMultiRoutineDayDeletesOnlyItsEvent() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        let arms = routine(name: "Arms")
        var schedule = WeeklySchedule()
        schedule.addRoutine(pushA.id, to: .monday)
        schedule.addRoutine(arms.id, to: .monday)

        let first = try await service.sync(request(schedule: schedule, routines: [pushA, arms]))
        let pushAKey = CalendarSyncService.eventKey(
            date: Self.monday(), routineID: pushA.id, calendar: Self.calendar()
        )
        let armsKey = CalendarSyncService.eventKey(
            date: Self.monday(), routineID: arms.id, calendar: Self.calendar()
        )
        let armsEventID = try #require(first[armsKey])

        schedule.removeRoutine(arms.id, from: .monday)
        let second = try await service.sync(
            request(schedule: schedule, routines: [pushA, arms], existingEventIDs: first)
        )

        #expect(fake.deletedIDs == [armsEventID])
        #expect(second[pushAKey] != nil)
        #expect(second[armsKey] == nil)
        #expect(fake.events.count == 1)
    }
}
