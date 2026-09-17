import Foundation
import GymCore

/// One cell of the month grid: what happened (or is planned) on that day.
struct MonthCalendarDay: Identifiable, Hashable {
    enum State: Hashable {
        /// A finished workout exists; `workoutID` opens its detail.
        case trained(workoutID: UUID, title: String)
        /// Routines are scheduled; `rescheduled` when the date carries an override.
        case planned(routineIDs: [UUID], title: String, rescheduled: Bool)
        case free
    }

    var id: String { key }
    let key: String
    let date: Date
    let dayNumber: Int
    let state: State
    let isToday: Bool
    let isPast: Bool
    /// Tonnage logged that day, for the calendar's lighter → heavier tint; 0 on a free day.
    var loadKg: Double = 0

    var workoutID: UUID? {
        if case .trained(let id, _) = state { return id }
        return nil
    }

    var plannedRoutineIDs: [UUID] {
        if case .planned(let ids, _, _) = state { return ids }
        return []
    }

    var isRescheduled: Bool {
        if case .planned(_, _, let rescheduled) = state { return rescheduled }
        return false
    }

    var title: String? {
        switch state {
        case .trained(_, let title), .planned(_, let title, _): title
        case .free: nil
        }
    }
}

/// Pure layout of a month for the calendar sheet: leading blanks so day 1 lands on its
/// weekday, then one `MonthCalendarDay` per day. A finished workout on a date wins over a
/// planned one, so a day never shows as both.
struct MonthCalendarModel: Hashable {
    let monthStart: Date
    let leadingBlanks: Int
    let days: [MonthCalendarDay]

    init(
        month: Date, records: [WorkoutRecord], schedule: WeeklySchedule, routines: [RoutineInfo],
        calendar: Calendar, now: Date = Date()
    ) {
        let components = calendar.dateComponents([.year, .month], from: month)
        let start = calendar.date(from: components) ?? month
        monthStart = start
        let weekday = calendar.component(.weekday, from: start)
        leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let today = calendar.startOfDay(for: now)
        let trained = Dictionary(grouping: records) { DateKey.string(for: $0.date, calendar: calendar) }
        days = (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = DateKey.string(for: date, calendar: calendar)
            let state: MonthCalendarDay.State
            var loadKg = 0.0
            if let record = trained[key]?.min(by: { $0.date < $1.date }) {
                state = .trained(workoutID: record.id, title: record.title)
                loadKg = trained[key]?.reduce(0) { $0 + $1.volumeKg } ?? 0
            } else {
                let ids = schedule.routineIDs(on: date, calendar: calendar)
                let planned = ids.compactMap { id in routines.first { $0.id == id } }
                if planned.isEmpty {
                    state = .free
                } else {
                    state = .planned(
                        routineIDs: planned.map(\.id), title: RoutineInfo.joinedNames(planned),
                        rescheduled: schedule.isRescheduled(date, calendar: calendar)
                    )
                }
            }
            return MonthCalendarDay(
                key: key, date: date, dayNumber: offset + 1, state: state,
                isToday: calendar.isDate(date, inSameDayAs: today), isPast: date < today, loadKg: loadKg
            )
        }
    }

    /// The month's heaviest day — the top of the calendar's tint ramp.
    var maxLoadKg: Double { days.map(\.loadKg).max() ?? 0 }

    var trainedCount: Int { days.filter { $0.workoutID != nil }.count }
    var plannedCount: Int { days.filter { !$0.plannedRoutineIDs.isEmpty }.count }
}
