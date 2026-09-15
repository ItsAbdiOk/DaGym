import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// The saved weekly schedule, or an empty one if nothing has ever been saved.
    func schedule() -> WeeklySchedule {
        guard let model = fetchScheduleModel() else { return WeeklySchedule() }
        guard let data = model.scheduleJSON.data(using: .utf8) else { return WeeklySchedule() }
        return (try? JSONDecoder().decode(WeeklySchedule.self, from: data)) ?? WeeklySchedule()
    }

    /// Upserts the single schedule row with `schedule` encoded as JSON.
    func saveSchedule(_ schedule: WeeklySchedule) {
        guard let data = try? JSONEncoder().encode(schedule), let json = String(data: data, encoding: .utf8)
        else { return }
        let model = fetchScheduleModel() ?? {
            let created = ScheduleModel()
            context.insert(created)
            return created
        }()
        model.scheduleJSON = json
        model.updatedAt = Date()
        save()
    }

    /// Today's planned routines, in the order they merge when the day is started. Falls back
    /// to the first saved routine (the original Home behaviour) only when no schedule has ever
    /// been saved, so existing users see no change until they visit the schedule screen.
    func todaysRoutines(calendar: Calendar = .current, now: Date = Date()) -> [RoutineInfo] {
        todaysRoutines(from: routines(), schedule: schedule(), calendar: calendar, now: now)
    }

    /// `todaysRoutines()` over a routine list and schedule already read — `RootView` refreshes
    /// all three of its routine facts from one fetch rather than three.
    func todaysRoutines(
        from all: [RoutineInfo], schedule currentSchedule: WeeklySchedule, calendar: Calendar = .current,
        now: Date = Date()
    ) -> [RoutineInfo] {
        guard !currentSchedule.dayRoutines.isEmpty || !currentSchedule.dateOverrides.isEmpty else {
            return all.first.map { [$0] } ?? []
        }
        return currentSchedule.routineIDs(on: now, calendar: calendar).compactMap { id in
            all.first { $0.id == id }
        }
    }

    /// The first of `todaysRoutines()` — what Home's headline and the widget show.
    func todaysRoutine(calendar: Calendar = .current, now: Date = Date()) -> RoutineInfo? {
        todaysRoutines(calendar: calendar, now: now).first
    }

    /// Starts a session from an ordered list of routines: the first one the usual way, the rest
    /// appended via `appendRoutine(id:to:)`. An empty list starts a freestyle session.
    func startWorkout(routineIDs: [UUID], calendar: Calendar = .current) -> WorkoutSession {
        guard let first = routineIDs.first else { return startFreestyle() }
        let session = startWorkout(routineID: first, calendar: calendar)
        for id in routineIDs.dropFirst() {
            appendRoutine(id: id, to: session, calendar: calendar)
        }
        return session
    }

    /// The next planned session after today, for the rest-day card
    /// ("Next: Pull B · Thursday"). `nil` when nothing is scheduled within
    /// the lookahead window or the scheduled routine no longer exists.
    func nextSession(
        calendar: Calendar = .current, now: Date = Date()
    ) -> (date: Date, routine: RoutineInfo)? {
        nextSession(from: routines(), schedule: schedule(), calendar: calendar, now: now)
    }

    /// `nextSession()` over a routine list and schedule already read (see `todaysRoutines(from:)`).
    func nextSession(
        from all: [RoutineInfo], schedule currentSchedule: WeeklySchedule, calendar: Calendar = .current,
        now: Date = Date()
    ) -> (date: Date, routine: RoutineInfo)? {
        // Days whose routines no longer exist are skipped rather than ending the search: the
        // old version took the planned day's *first* routine id and gave up when it had been
        // deleted, so one stale id blanked Home's "Next:" card entirely instead of showing the
        // session after it.
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let next = currentSchedule.nextSession(
            after: now, calendar: calendar, where: { byID[$0] != nil }
        ), let routine = byID[next.routineID] else { return nil }
        return (next.date, routine)
    }

    /// When the schedule row was last written, for `CoachInput.scheduleUpdatedAt` — the coach's
    /// adherence rule refuses to grade weeks that began before the current plan existed.
    func scheduleUpdatedAt() -> Date? {
        fetchScheduleModel()?.updatedAt
    }

    /// Drops `routineID` from every weekday and every date override, returning whether anything
    /// changed. Called when a routine is deleted: leaving the id behind left the schedule
    /// pointing at a routine that no longer exists, which showed as a blank planned day and
    /// (via `nextSession`) a blank "Next:" card.
    @discardableResult
    func removeRoutineFromSchedule(id routineID: UUID) -> Bool {
        var current = schedule()
        var changed = false
        for (weekday, list) in current.dayRoutines where list.contains(routineID) {
            current.setRoutines(list.filter { $0 != routineID }, on: weekday)
            changed = true
        }
        for (key, list) in current.dateOverrides where list.contains(routineID) {
            current.dateOverrides[key] = list.filter { $0 != routineID }
            changed = true
        }
        guard changed else { return false }
        saveSchedule(current)
        return true
    }

    /// Event identifiers written by the last calendar sync, keyed by
    /// `GymCore.DateKey` string. Read/written alongside the schedule so
    /// re-syncing stays idempotent.
    func scheduleEventIDs() -> [String: String] {
        guard let model = fetchScheduleModel(), let data = model.eventIDsJSON.data(using: .utf8) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func saveScheduleEventIDs(_ eventIDs: [String: String]) {
        guard let data = try? JSONEncoder().encode(eventIDs), let json = String(data: data, encoding: .utf8)
        else { return }
        let model = fetchScheduleModel() ?? {
            let created = ScheduleModel()
            context.insert(created)
            return created
        }()
        model.eventIDsJSON = json
        save()
    }

    private static func newestScheduleFirst() -> FetchDescriptor<ScheduleModel> {
        FetchDescriptor<ScheduleModel>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
    }

    /// The newest schedule row. CloudKit can merge one per device; the most recently saved wins
    /// and `dedupeScheduleRows()` removes the rest.
    private func fetchScheduleModel() -> ScheduleModel? {
        var descriptor = Self.newestScheduleFirst()
        descriptor.fetchLimit = 1
        return fetchFirst(descriptor)
    }

    /// Keeps only the most recently updated schedule row, folding each older row's calendar
    /// event ids into it so a re-sync can still find events the other device created.
    @discardableResult
    func dedupeScheduleRows() -> Int {
        let rows = fetch(Self.newestScheduleFirst())
        guard let survivor = rows.first, rows.count > 1 else { return 0 }
        var eventIDs = scheduleEventIDs()
        for extra in rows.dropFirst() {
            if let data = extra.eventIDsJSON.data(using: .utf8),
               let theirs = try? JSONDecoder().decode([String: String].self, from: data) {
                eventIDs.merge(theirs) { mine, _ in mine }
            }
            context.delete(extra)
        }
        if let data = try? JSONEncoder().encode(eventIDs), let json = String(data: data, encoding: .utf8) {
            survivor.eventIDsJSON = json
        }
        save()
        return rows.count - 1
    }
}
