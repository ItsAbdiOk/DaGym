import Foundation
import GymCore

/// What one `ConsistencyWidget` entry renders, resolved for a particular day from the
/// snapshot's `dailySets`. Shared between the `DaGym` and `DaGymWidgets` targets (see
/// `project.yml`) so `WidgetConsistencyTests` can drive the derivation without the widget target.
struct WidgetConsistency: Equatable {
    /// Week columns of 7 day slots, oldest week first, laid out by `ConsistencyCalendar.monthGrid`
    /// — `nil` before the window starts and after the entry's day. Each cell's `level` is the
    /// same 0…4 sets quantile the Consistency screen shades by.
    var grid: [[DayCell?]]
    /// Days in the window with at least one counted set, and the window's length.
    var trainedDays: Int
    var totalDays: Int
    /// The calendar week containing the entry's day, `firstWeekday` first: `true` where a
    /// workout landed. Days after the entry are `false`.
    var thisWeek: [Bool]
    var thisWeekWorkouts: Int
    var thisWeekSets: Int
    /// This week's volume in kg, or `nil` when the snapshot was written in an earlier week (its
    /// figure would describe the wrong week) or has no data yet.
    var weekVolumeKg: Double?

    /// "Trained 31 of 91 days, 4 this week" — the whole widget in one VoiceOver line, since the
    /// squares themselves are far too small to be individual targets.
    var accessibilityLabel: String {
        "Trained \(trainedDays) of \(totalDays) days, \(thisWeekWorkouts) this week"
    }

    static let empty = WidgetConsistency(
        grid: [], trainedDays: 0, totalDays: 0, thisWeek: Array(repeating: false, count: 7),
        thisWeekWorkouts: 0, thisWeekSets: 0, weekVolumeKg: nil
    )
}

extension WidgetSnapshot {
    /// The most days `dailySets` carries: 26 weeks, the large widget's window.
    static let maxConsistencyDays = 26 * 7

    /// The calendar week containing `date` plus the `weeks - 1` before it — exactly `weeks`
    /// columns, the current one part-filled — run through the Consistency screen's own bucketing
    /// (`ConsistencyCalendar.cells` → `monthGrid`) so the widget and the Progress tab can never
    /// disagree about a day's shade. Days after the snapshot was written count as untrained
    /// rather than unknown — the app reloads the widget the moment a workout finishes.
    func consistency(weeks: Int, on date: Date) -> WidgetConsistency {
        guard hasData, weeks > 0 else { return .empty }
        let calendar = calendar
        let end = calendar.startOfDay(for: date)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: end)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart) else {
            return .empty
        }
        let totalDays = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let byDay = setsByDay(calendar: calendar)
        let workouts = byDay.map { (date: $0.key, sets: $0.value, minutes: 0) }
        let cells = ConsistencyCalendar.cells(workouts: workouts, from: start, to: end, calendar: calendar)
        let week = Self.thisWeek(byDay: byDay, on: end, calendar: calendar)
        let sameWeek = calendar.isDate(updatedAt, equalTo: date, toGranularity: .weekOfYear)
        return WidgetConsistency(
            grid: ConsistencyCalendar.monthGrid(cells: cells, calendar: calendar),
            trainedDays: cells.filter { $0.sets > 0 }.count,
            totalDays: totalDays,
            thisWeek: week.map { $0 > 0 },
            thisWeekWorkouts: week.filter { $0 > 0 }.count,
            thisWeekSets: week.reduce(0, +),
            weekVolumeKg: sameWeek ? weekVolumeKg : nil
        )
    }

    /// Start-of-day → counted sets, from `dailySets`. A snapshot written before that field
    /// existed still has `workoutDays`; each of those counts as one set, so an un-updated widget
    /// shows trained days at a flat shade instead of nothing.
    private func setsByDay(calendar: Calendar) -> [Date: Int] {
        var byDay: [Date: Int] = [:]
        if let dailySetsStart, !dailySets.isEmpty {
            let start = calendar.startOfDay(for: dailySetsStart)
            for (offset, sets) in dailySets.enumerated() where sets > 0 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                byDay[day, default: 0] += sets
            }
        } else {
            for day in workoutDays {
                byDay[calendar.startOfDay(for: day), default: 0] += 1
            }
        }
        return byDay
    }

    /// Sets per day of the calendar week containing `day`, `firstWeekday` first; days after
    /// `day` are 0.
    private static func thisWeek(byDay: [Date: Int], on day: Date, calendar: Calendar) -> [Int] {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start else {
            return Array(repeating: 0, count: 7)
        }
        return (0..<7).map { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart), date <= day else {
                return 0
            }
            return byDay[calendar.startOfDay(for: date)] ?? 0
        }
    }
}
