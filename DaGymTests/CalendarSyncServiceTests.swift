import Foundation
import GymCore
import Testing

@testable import DaGym

/// One recorded event, keyed by id in `FakeEventStore.events`.
private struct StoredEvent {
    var title: String
    var start: Date
    var end: Date
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
        events[eventID] = StoredEvent(title: draft.title, start: draft.start, end: draft.end)
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

    private func routine(name: String) -> RoutineInfo {
        RoutineInfo(
            name: name, exercises: [], setCount: 0, estimatedMinutes: 50, progressionRule: "linear",
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

    @Test("first sync creates one event per planned session")
    func firstSyncCreatesEvents() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        let legs = routine(name: "Legs")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        schedule.days[.wednesday] = legs.id

        let eventIDs = try await service.sync(request(schedule: schedule, routines: [pushA, legs]))

        #expect(eventIDs.count == 2)
        #expect(fake.events.count == 2)
        #expect(fake.createCalendarCount == 1)
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
        let originalEventID = try #require(first[DateKey.string(for: monday, calendar: Self.calendar())])

        schedule.moved(date: monday, to: nil, calendar: Self.calendar())
        schedule.moved(date: thursday, to: pushA.id, calendar: Self.calendar())

        let second = try await service.sync(
            request(schedule: schedule, routines: [pushA], existingEventIDs: first)
        )

        #expect(fake.deletedIDs == [originalEventID])
        #expect(second[DateKey.string(for: thursday, calendar: Self.calendar())] != nil)
        #expect(second[DateKey.string(for: monday, calendar: Self.calendar())] == nil)
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
}
