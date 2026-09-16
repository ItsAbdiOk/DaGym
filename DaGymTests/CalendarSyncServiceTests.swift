import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// One recorded event, keyed by id in `FakeEventStore.events`.
struct StoredEvent {
    var title: String
    var start: Date
    var end: Date
    var notes: String
    var url: URL?
}

/// Records every call so tests can assert on it without touching EventKit.
///
/// Crucially this now **models what EventKit actually does under each access level**. The old
/// fake found events by identifier and listed calendars unconditionally, whatever access had
/// been granted — which is exactly why the suite could not see that the service was asking for
/// write-only access while depending on reads.
final class FakeEventStore: EventStoring, @unchecked Sendable {
    var access: CalendarAccess = .full
    var createCalendarError: Error?
    private var storedCalendars: [CalendarInfo] = []
    private(set) var events: [String: StoredEvent] = [:]
    private(set) var deletedIDs: [String] = []
    private(set) var createCalendarCount = 0
    private var nextEventNumber = 0

    private(set) var requestAccessCount = 0

    func requestAccess() async throws -> CalendarAccess {
        requestAccessCount += 1
        return access
    }

    func currentAccess() -> CalendarAccess { access }

    /// `EKEventStore.calendars(for:)` comes back empty under write-only access.
    func calendars() -> [CalendarInfo] { access == .full ? storedCalendars : [] }

    func createCalendar(named name: String) throws -> String {
        if let createCalendarError { throw createCalendarError }
        createCalendarCount += 1
        let calendar = CalendarInfo(id: "cal-\(createCalendarCount)", title: name)
        storedCalendars.append(calendar)
        return calendar.id
    }

    /// Under write-only access `event(withIdentifier:)` returns nil, so an "update" silently
    /// becomes a brand-new event.
    func upsertEvent(id: String?, draft: EventDraft, calendarID: String) throws -> String {
        let existing = access == .full ? id : nil
        let eventID = existing ?? {
            nextEventNumber += 1
            return "event-\(nextEventNumber)"
        }()
        events[eventID] = StoredEvent(
            title: draft.title, start: draft.start, end: draft.end, notes: draft.notes, url: draft.url
        )
        return eventID
    }

    /// …and a delete is a no-op, because the event can't be looked up.
    func deleteEvent(id: String) throws {
        guard access == .full else { return }
        deletedIDs.append(id)
        events.removeValue(forKey: id)
    }

    func fetchEvents(inCalendar calendarID: String, from: Date, to: Date) throws -> [FetchedEvent] {
        guard access == .full else { return [] }
        return events
            .filter { $0.value.start >= from && $0.value.start < to }
            .map { FetchedEvent(id: $0.key, url: $0.value.url) }
    }

    /// Plants an event nothing is tracking — what a second device's sync leaves behind when
    /// CloudKit hasn't merged the two `ScheduleModel` rows yet.
    @discardableResult
    func plantOrphan(start: Date, routineID: UUID) -> String {
        nextEventNumber += 1
        let id = "orphan-\(nextEventNumber)"
        events[id] = StoredEvent(
            title: "DaGym · Ghost", start: start, end: start, notes: "",
            url: URL(string: "dagym://start?routine=\(routineID.uuidString)")
        )
        return id
    }

    /// An event the lifter put in the DaGym calendar themselves — no `dagym://` URL.
    @discardableResult
    func plantUserEvent(start: Date) -> String {
        nextEventNumber += 1
        let id = "user-\(nextEventNumber)"
        events[id] = StoredEvent(title: "Physio", start: start, end: start, notes: "", url: nil)
        return id
    }
}

@Suite("Calendar sync")
struct CalendarSyncServiceTests {
    private static func calendar(
        timeZone: String = "UTC", firstWeekday: Int = 2
    ) -> Calendar {
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

    /// Monday 2026-01-05.
    private static func monday() -> Date { date(2026, 1, 5) }

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
        schedule: WeeklySchedule, routines: [RoutineInfo], existingEventIDs: [String: String] = [:],
        startDate: Date = CalendarSyncServiceTests.monday(), days: Int = 7,
        calendar: Calendar = CalendarSyncServiceTests.calendar()
    ) -> ScheduleSyncRequest {
        ScheduleSyncRequest(
            schedule: schedule, routines: routines, startDate: startDate, days: days,
            defaultStartHour: 18, existingEventIDs: existingEventIDs, calendar: calendar
        )
    }

    // MARK: - Baseline behaviour

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

    // MARK: - Access levels

    @Test("denied access throws instead of quietly reporting success")
    func deniedAccessThrows() async throws {
        let fake = FakeEventStore()
        fake.access = .denied
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id

        await #expect(throws: CalendarSyncError.accessDenied) {
            try await service.sync(request(schedule: schedule, routines: [pushA]))
        }
        #expect(fake.events.isEmpty)
        #expect(fake.createCalendarCount == 0)
    }

    /// The defect this whole fake was rebuilt for. Under "Add Events Only" EventKit can't look
    /// an event up by identifier, so a second sync would create a *second* copy of every
    /// session and delete nothing — and `calendars(for:)` being empty meant a fresh "DaGym"
    /// calendar on every sync too. The service now refuses rather than doing that.
    @Test("write-only access is refused, not silently duplicated")
    func writeOnlyAccessIsRefused() async throws {
        let fake = FakeEventStore()
        fake.access = .writeOnly
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        schedule.days[.wednesday] = pushA.id
        schedule.days[.friday] = pushA.id

        await #expect(throws: CalendarSyncError.writeOnlyAccess) {
            try await service.sync(request(schedule: schedule, routines: [pushA]))
        }
        #expect(fake.events.isEmpty)
        #expect(fake.createCalendarCount == 0)
    }

    // MARK: - The coordinator both screens now go through

    /// The Settings toggle used to run its own `try? await service.sync(request)` chain, so
    /// denying calendar access left the switch on and the schedule footnote still claiming
    /// "Synced to your \"DaGym\" calendar." Both screens go through `CalendarSyncCoordinator`
    /// now: a refusal comes back as an `Outcome`, turns `calendarSyncEnabled` back off, and
    /// carries the message the UI shows.
    @Test("a refused sync turns the preference back off and says why")
    @MainActor
    func refusedSyncDisablesThePreferenceAndExplains() async throws {
        let store = try makeStore()
        let defaults = UserDefaults(suiteName: "calendar-sync-coordinator") ?? .standard
        defaults.removePersistentDomain(forName: "calendar-sync-coordinator")
        let preferences = Preferences(suite: defaults)
        preferences.calendarSyncEnabled = true

        let fake = FakeEventStore()
        fake.access = .denied
        let outcome = await CalendarSyncCoordinator.sync(
            store: store, preferences: preferences, eventStore: fake
        )

        #expect(outcome == CalendarSyncCoordinator.Outcome.denied(.accessDenied))
        #expect(preferences.calendarSyncEnabled == false)
        #expect(outcome.problemMessage?.isEmpty == false)
        #expect(fake.events.isEmpty)
        #expect(store.scheduleEventIDs().isEmpty)
    }

    /// And the ordinary case stays quiet: nothing for either screen to report.
    @Test("a successful sync reports no problem for the UI to show")
    @MainActor
    func successfulSyncHasNoProblemMessage() async throws {
        let store = try makeStore()
        let defaults = UserDefaults(suiteName: "calendar-sync-coordinator-ok") ?? .standard
        defaults.removePersistentDomain(forName: "calendar-sync-coordinator-ok")
        let preferences = Preferences(suite: defaults)
        preferences.calendarSyncEnabled = true

        let outcome = await CalendarSyncCoordinator.sync(
            store: store, preferences: preferences, eventStore: FakeEventStore()
        )

        #expect(outcome.problemMessage == nil)
        #expect(preferences.calendarSyncEnabled)
    }

    @Test("a calendar source that refuses new calendars surfaces its error")
    func createCalendarErrorPropagates() async throws {
        struct Refused: Error {}
        let fake = FakeEventStore()
        fake.createCalendarError = Refused()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id

        await #expect(throws: Refused.self) {
            try await service.sync(request(schedule: schedule, routines: [pushA]))
        }
    }
}
