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

    /// Today's planned routine. Falls back to the first saved routine (the
    /// original Home behaviour) only when no schedule has ever been saved,
    /// so existing users see no change until they visit the schedule screen.
    func todaysRoutine(calendar: Calendar = .current, now: Date = Date()) -> RoutineInfo? {
        let currentSchedule = schedule()
        let all = routines()
        guard !currentSchedule.days.isEmpty || !currentSchedule.overrides.isEmpty else {
            return all.first
        }
        guard let routineID = currentSchedule.routineID(on: now, calendar: calendar) else { return nil }
        return all.first { $0.id == routineID }
    }

    /// The next planned session after today, for the rest-day card
    /// ("Next: Pull B · Thursday"). `nil` when nothing is scheduled within
    /// the lookahead window or the scheduled routine no longer exists.
    func nextSession(
        calendar: Calendar = .current, now: Date = Date()
    ) -> (date: Date, routine: RoutineInfo)? {
        guard let next = schedule().nextSession(after: now, calendar: calendar) else { return nil }
        guard let routine = routines().first(where: { $0.id == next.routineID }) else { return nil }
        return (next.date, routine)
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

    private func fetchScheduleModel() -> ScheduleModel? {
        var descriptor = FetchDescriptor<ScheduleModel>()
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
