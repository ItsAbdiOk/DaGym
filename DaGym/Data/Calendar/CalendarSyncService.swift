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

/// One event read back out of the DaGym calendar, for orphan reconciliation.
struct FetchedEvent: Sendable, Hashable {
    var id: String
    var url: URL?

    /// Whether DaGym wrote this event: every event `CalendarSyncService` creates carries a
    /// `dagym://start?routine=…` URL, and nothing else does. Anything the lifter added to the
    /// DaGym calendar themselves is left strictly alone.
    var isDaGymEvent: Bool { url?.scheme == CalendarSyncService.urlScheme }
}

/// What the lifter actually granted. DaGym needs `full`: see `EventStoring`.
enum CalendarAccess: Sendable, Hashable {
    case denied
    case writeOnly
    case full
}

/// Why a sync could not run or complete. Surfaced (not swallowed) so the UI can turn the
/// calendar-sync toggle back off and say what happened, instead of leaving it on with a
/// footnote claiming the schedule is "Synced to your DaGym calendar".
enum CalendarSyncError: Error, Equatable {
    case accessDenied
    case writeOnlyAccess
}

/// Storage abstraction over EventKit so `CalendarSyncService` can run against a fake in tests.
///
/// **Full access is required, and write-only is explicitly rejected.** The sync is an *upsert*:
/// it has to find the event it created for a given day+routine in order to update it when the
/// session moves or the routine is renamed, and to remove it when the day is cleared. Under
/// write-only access `EKEventStore.event(withIdentifier:)` returns nil and `calendars(for:)`
/// comes back empty, so every "update" silently created a brand-new event, every delete was a
/// no-op, and a new "DaGym" calendar was created on each sync. A Mon/Wed/Fri plan that had 6
/// events grew by ~14 more every time the lifter touched their schedule, forever, with no way
/// to ever clean them up. There is no design that is correct under write-only — you cannot
/// revise what you cannot look up — so DaGym asks for full access and refuses to sync without
/// it. It still only ever reads its own "DaGym" calendar (plan.md §6.8).
protocol EventStoring: Sendable {
    func requestAccess() async throws -> CalendarAccess
    func calendars() -> [CalendarInfo]
    func createCalendar(named name: String) throws -> String
    /// Creates a new event when `id` is `nil`, otherwise updates the
    /// existing event with that identifier (recreating it if EventKit no
    /// longer has it). Returns the event's identifier either way.
    @discardableResult
    func upsertEvent(id: String?, draft: EventDraft, calendarID: String) throws -> String
    func deleteEvent(id: String) throws
    func fetchEvents(inCalendar calendarID: String, from: Date, to: Date) throws -> [FetchedEvent]
}

/// Real `EventStoring` backed by `EKEventStore`.
final class EventKitStore: EventStoring, @unchecked Sendable {
    private let store = EKEventStore()

    func requestAccess() async throws -> CalendarAccess {
        _ = try await store.requestFullAccessToEvents()
        return Self.access(for: EKEventStore.authorizationStatus(for: .event))
    }

    /// A lifter who granted "Add Events Only" on an older build lands here as `.writeOnly`;
    /// `requestFullAccessToEvents()` re-prompts them to upgrade, and until they do the sync
    /// refuses to run rather than quietly duplicating their week.
    static func access(for status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: .full
        case .writeOnly: .writeOnly
        default: .denied
        }
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

    func fetchEvents(inCalendar calendarID: String, from: Date, to: Date) throws -> [FetchedEvent] {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        return store.events(matching: predicate).map { FetchedEvent(id: $0.eventIdentifier, url: $0.url) }
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
    /// How far back event identifiers keep being remembered. Their events are never touched;
    /// this only bounds how large the persisted map can grow.
    var retentionDays = 90
}

/// Mirrors a `WeeklySchedule` onto a dedicated "DaGym" calendar: one event per planned
/// routine, keyed by calendar day + routine id so re-syncing is idempotent and moving,
/// clearing, or removing one routine from a multi-routine day updates or removes just its
/// event, leaving the day's other routines' events untouched.
struct CalendarSyncService: Sendable {
    static let calendarName = "DaGym"
    static let urlScheme = "dagym"

    /// The `existingEventIDs` key for one routine planned on one day. Composite (rather than
    /// just the day) so a day with several routines gets one event each instead of one merged
    /// event, and so removing a single routine from that day only ever deletes its own key.
    static func eventKey(date: Date, routineID: UUID, calendar: Calendar) -> String {
        "\(DateKey.string(for: date, calendar: calendar))#\(routineID.uuidString)"
    }

    /// The calendar day a tracked key refers to — the part before the `#`. Also parses the
    /// original day-only keys this map used before multi-routine days existed.
    static func date(forKey key: String, calendar: Calendar) -> Date? {
        DateKey.date(from: String(key.prefix { $0 != "#" }), calendar: calendar)
    }

    var eventStore: EventStoring

    /// Upserts one event per planned session in `[startOfDay(startDate), +days)`, deletes the
    /// events of days **inside that window** that used to have a planned session but no longer
    /// do, and leaves everything outside the window alone. Returns the new key → eventID map to
    /// persist via `WorkoutStore.saveScheduleEventIDs`.
    ///
    /// The window bound on deletion is the point: the old code deleted every tracked key that
    /// wasn't re-planned, which included every day *before* `startDate` — so editing the
    /// schedule on the 22nd erased the lifter's own calendar record of the 14th–21st. Past keys
    /// are now carried forward untouched (and simply forgotten, without deleting their events,
    /// once they age past `retentionDays`).
    @discardableResult
    func sync(_ request: ScheduleSyncRequest) async throws -> [String: String] {
        switch try await eventStore.requestAccess() {
        case .denied: throw CalendarSyncError.accessDenied
        case .writeOnly: throw CalendarSyncError.writeOnlyAccess
        case .full: break
        }
        let calendarID = try resolveCalendarID()
        let window = Self.window(for: request)
        let planned = request.schedule.plannedSessions(
            from: window.lowerBound, days: request.days, calendar: request.calendar
        )
        let routinesByID = Dictionary(uniqueKeysWithValues: request.routines.map { ($0.id, $0) })
        let tracked = Self.adoptingLegacyKeys(
            request.existingEventIDs, planned: planned, calendar: request.calendar
        )

        var updated: [String: String] = [:]
        for (date, routineID) in planned {
            guard let routine = routinesByID[routineID] else { continue }
            let key = Self.eventKey(date: date, routineID: routineID, calendar: request.calendar)
            let draft = eventDraft(for: routine, on: date, request: request)
            updated[key] = try eventStore.upsertEvent(
                id: tracked[key], draft: draft, calendarID: calendarID
            )
        }
        reconcile(tracked: tracked, into: &updated, window: window, request: request)
        removeOrphans(calendarID: calendarID, keeping: Set(updated.values), window: window)
        return updated
    }

    /// The half-open day range this sync is responsible for. Anchored to the *start of the day*
    /// containing `startDate` so a sync at 21:00 still owns today's own event.
    private static func window(for request: ScheduleSyncRequest) -> Range<Date> {
        let start = request.calendar.startOfDay(for: request.startDate)
        let end = request.calendar.date(byAdding: .day, value: max(0, request.days), to: start) ?? start
        return start..<max(end, start)
    }

    /// Folds this map's original day-only keys (`"2026-01-05"`, from before a day could hold
    /// several routines) onto the composite key of that day's **first** planned routine, so an
    /// upgrade re-uses the existing event instead of abandoning it and creating a duplicate
    /// alongside it.
    private static func adoptingLegacyKeys(
        _ existing: [String: String], planned: [(date: Date, routineID: UUID)], calendar: Calendar
    ) -> [String: String] {
        var result = existing
        var claimed: Set<String> = []
        for (date, routineID) in planned {
            let dayKey = DateKey.string(for: date, calendar: calendar)
            guard !claimed.contains(dayKey), let legacy = result[dayKey] else { continue }
            claimed.insert(dayKey)
            let key = eventKey(date: date, routineID: routineID, calendar: calendar)
            if result[key] == nil { result[key] = legacy }
            result.removeValue(forKey: dayKey)
        }
        return result
    }

    /// Decides what happens to every tracked key the plan didn't just rewrite: delete inside the
    /// window (the session really was cancelled), keep outside it (the past, and days beyond the
    /// look-ahead that will come back into range), forget beyond the retention horizon.
    private func reconcile(
        tracked: [String: String], into updated: inout [String: String],
        window: Range<Date>, request: ScheduleSyncRequest
    ) {
        let horizon = request.calendar.date(
            byAdding: .day, value: -max(0, request.retentionDays), to: window.lowerBound
        ) ?? window.lowerBound
        for (key, eventID) in tracked where updated[key] == nil {
            guard let date = Self.date(forKey: key, calendar: request.calendar) else { continue }
            if window.contains(date) {
                try? eventStore.deleteEvent(id: eventID)
            } else if date >= horizon {
                updated[key] = eventID
            }
        }
    }

    /// Deletes DaGym-written events inside the window that nothing is tracking any more.
    ///
    /// Two devices can both sync the same day before CloudKit has merged their `ScheduleModel`
    /// rows, and the loser's event identifier is then lost with its row — leaving a duplicate
    /// session sitting in the shared "DaGym" calendar with nothing left that can ever remove it.
    /// Reconciling against what's actually in the calendar is the only way to collect those.
    /// Events without DaGym's own `dagym://` URL are never touched.
    private func removeOrphans(calendarID: String, keeping known: Set<String>, window: Range<Date>) {
        let existing = (try? eventStore.fetchEvents(
            inCalendar: calendarID, from: window.lowerBound, to: window.upperBound
        )) ?? []
        for event in existing where event.isDaGymEvent && !known.contains(event.id) {
            try? eventStore.deleteEvent(id: event.id)
        }
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
            url: URL(string: "\(Self.urlScheme)://start?routine=\(routine.id.uuidString)")
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

/// The one place a calendar sync is started from. Three things were wrong with syncing straight
/// from a view: it only ran from two settings screens (so the rolling 14-day window stopped
/// advancing 14 days after the last edit — `syncInBackground` now also runs on launch, on every
/// foreground and at midnight, via `RootView.refresh`); failures were swallowed by `try?` (so
/// denied access left the toggle on and the footnote still claiming "Synced" — an `Outcome`
/// comes back instead, and a refusal turns `calendarSyncEnabled` back off); and each screen kept
/// its own serialising `Task` chain, so two screens could still sync concurrently over the same
/// event ids and duplicate a week. The chain is process-wide now.
@MainActor
enum CalendarSyncCoordinator {
    enum Outcome: Equatable {
        /// `Preferences.calendarSyncEnabled` is off — nothing was attempted.
        case disabled
        case synced(events: Int)
        /// Access was refused, or only "Add Events Only" was granted (which cannot be synced
        /// correctly — see `EventStoring`). `calendarSyncEnabled` has been turned back off.
        case denied(CalendarSyncError)
        case failed(String)

        /// What the Schedule screen's footnote should say, or nil when there is nothing to say.
        var problemMessage: String? {
            switch self {
            case .disabled, .synced: nil
            case .denied(.accessDenied):
                "Calendar sync is off: DaGym doesn't have access to your calendars. "
                    + "Allow Full Access in Settings → Privacy → Calendars."
            case .denied(.writeOnlyAccess):
                "Calendar sync is off: \"Add Events Only\" isn't enough to keep your sessions "
                    + "up to date. Allow Full Access in Settings → Privacy → Calendars."
            case .failed(let message): "Couldn't update your \"DaGym\" calendar: \(message)"
            }
        }
    }

    /// Serialises every sync in the process: two overlapping runs would read the same
    /// `existingEventIDs` and each create its own copy of the week.
    private static var chain: Task<Void, Never> = Task {}

    @discardableResult
    static func sync(
        store: WorkoutStore, preferences: Preferences, eventStore: EventStoring = EventKitStore(),
        now: Date = Date(), calendar: Calendar = .current
    ) async -> Outcome {
        guard preferences.calendarSyncEnabled else { return .disabled }
        let previous = chain
        let task = Task { @MainActor () -> Outcome in
            await previous.value
            return await run(
                store: store, preferences: preferences, eventStore: eventStore, now: now,
                calendar: calendar
            )
        }
        chain = Task { _ = await task.value }
        return await task.value
    }

    /// Fire-and-forget entry point for the places that can't await (a `View` body's lifecycle
    /// hooks). Inert in a test process, like `WidgetSnapshotWriter.live` and
    /// `ResetSideEffects.live`: a unit or UI test must never touch the developer's real calendar
    /// or trigger a permission prompt.
    static func syncInBackground(store: WorkoutStore, preferences: Preferences) {
        guard !LaunchFlags.isTesting, preferences.calendarSyncEnabled else { return }
        Task { await sync(store: store, preferences: preferences) }
    }

    private static func run(
        store: WorkoutStore, preferences: Preferences, eventStore: EventStoring, now: Date,
        calendar: Calendar
    ) async -> Outcome {
        let service = CalendarSyncService(eventStore: eventStore)
        let request = ScheduleSyncRequest(
            schedule: store.schedule(), routines: store.routines(), startDate: now,
            defaultStartHour: preferences.scheduledStartHour,
            existingEventIDs: store.scheduleEventIDs(), calendar: calendar
        )
        do {
            let updated = try await service.sync(request)
            store.saveScheduleEventIDs(updated)
            return .synced(events: updated.count)
        } catch let error as CalendarSyncError {
            preferences.calendarSyncEnabled = false
            return .denied(error)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
