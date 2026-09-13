import EventKit
import Foundation
import GymCore
import UIKit

/// One calendar EventKit knows about (either DaGym's own, or another the
/// user already has).
struct CalendarInfo: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
}

/// The fields of one calendar event, bundled so `upsertEvent` stays under
/// the lint's parameter-count limit.
struct EventDraft: Sendable {
    var title: String
    var start: Date
    var end: Date
    var notes: String
    var url: URL?
}

/// Storage abstraction over EventKit so `CalendarSyncService` can run
/// against a fake in tests. Write-only access is enough for everything
/// DaGym does: create/update/delete events in its own "DaGym" calendar.
/// Never reads the user's other events (plan.md §6.8).
protocol EventStoring: Sendable {
    func requestWriteOnlyAccess() async throws -> Bool
    func calendars() -> [CalendarInfo]
    func createCalendar(named name: String) throws -> String
    /// Creates a new event when `id` is `nil`, otherwise updates the
    /// existing event with that identifier (recreating it if EventKit no
    /// longer has it). Returns the event's identifier either way.
    @discardableResult
    func upsertEvent(id: String?, draft: EventDraft, calendarID: String) throws -> String
    func deleteEvent(id: String) throws
    func fetchEvents(inCalendar calendarID: String, from: Date, to: Date) throws -> [String]
}

/// Real `EventStoring` backed by `EKEventStore`.
final class EventKitStore: EventStoring, @unchecked Sendable {
    private let store = EKEventStore()

    func requestWriteOnlyAccess() async throws -> Bool {
        try await store.requestWriteOnlyAccessToEvents()
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
    }

    func createCalendar(named name: String) throws -> String {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = name
        calendar.cgColor = UIColor(red: 0xF4 / 255, green: 0x70 / 255, blue: 0x5C / 255, alpha: 1).cgColor
        let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar.calendarIdentifier
    }

    func upsertEvent(id: String?, draft: EventDraft, calendarID: String) throws -> String {
        let event = id.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.notes = draft.notes
        event.url = draft.url
        event.calendar = store.calendar(withIdentifier: calendarID) ?? event.calendar
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    func deleteEvent(id: String) throws {
        guard let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent)
    }

    func fetchEvents(inCalendar calendarID: String, from: Date, to: Date) throws -> [String] {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        return store.events(matching: predicate).map(\.eventIdentifier)
    }
}

/// Everything `CalendarSyncService.sync(_:)` needs, bundled so the method
/// stays under the lint's parameter-count limit.
struct ScheduleSyncRequest {
    var schedule: WeeklySchedule
    var routines: [RoutineInfo]
    var startDate: Date
    var days = 14
    var sessionMinutes: (RoutineInfo) -> Int = \.estimatedMinutes
    var defaultStartHour: Int
    var existingEventIDs: [String: String]
    var calendar: Calendar = .current
}

/// Mirrors a `WeeklySchedule` onto a dedicated "DaGym" calendar: one event
/// per planned session, keyed by calendar day so re-syncing is idempotent
/// and moving or clearing a day updates or removes just that event.
struct CalendarSyncService: Sendable {
    static let calendarName = "DaGym"

    var eventStore: EventStoring

    /// Upserts one event per planned session in `[startDate, startDate +
    /// days)` and deletes events for calendar days that used to have a
    /// planned session (per `existingEventIDs`) but no longer do. Returns
    /// the new dateKey → eventID map to persist via
    /// `WorkoutStore.saveScheduleEventIDs`.
    @discardableResult
    func sync(_ request: ScheduleSyncRequest) async throws -> [String: String] {
        guard try await eventStore.requestWriteOnlyAccess() else { return request.existingEventIDs }
        let calendarID = try resolveCalendarID()
        let planned = request.schedule.plannedSessions(
            from: request.startDate, days: request.days, calendar: request.calendar
        )
        let routinesByID = Dictionary(uniqueKeysWithValues: request.routines.map { ($0.id, $0) })

        var updatedEventIDs: [String: String] = [:]
        for (date, routineID) in planned {
            guard let routine = routinesByID[routineID] else { continue }
            let key = DateKey.string(for: date, calendar: request.calendar)
            let draft = eventDraft(for: routine, on: date, request: request)
            let eventID = try eventStore.upsertEvent(
                id: request.existingEventIDs[key], draft: draft, calendarID: calendarID
            )
            updatedEventIDs[key] = eventID
        }

        for (key, eventID) in request.existingEventIDs where updatedEventIDs[key] == nil {
            try? eventStore.deleteEvent(id: eventID)
        }
        return updatedEventIDs
    }

    private func eventDraft(
        for routine: RoutineInfo, on date: Date, request: ScheduleSyncRequest
    ) -> EventDraft {
        let start = startTime(for: date, hour: request.defaultStartHour, calendar: request.calendar)
        let minutes = max(15, request.sessionMinutes(routine))
        let end = request.calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
        return EventDraft(
            title: "DaGym · \(routine.name)", start: start, end: end,
            notes: routine.exercises.map(\.name).joined(separator: "\n"),
            url: URL(string: "dagym://start?routine=\(routine.id.uuidString)")
        )
    }

    private func resolveCalendarID() throws -> String {
        if let existing = eventStore.calendars().first(where: { $0.title == Self.calendarName }) {
            return existing.id
        }
        return try eventStore.createCalendar(named: Self.calendarName)
    }

    private func startTime(for date: Date, hour: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        return calendar.date(from: components) ?? date
    }
}
