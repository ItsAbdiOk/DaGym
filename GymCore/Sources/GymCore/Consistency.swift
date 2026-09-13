import Foundation

/// One day's training activity for the consistency heatmap.
public struct DayCell: Sendable, Hashable {
    public var date: Date
    /// 0 (no sets) … 4 (busiest tier), relative to the busiest day in the range — see
    /// `ConsistencyCalendar.cells(workouts:from:to:calendar:)`.
    public var level: Int
    public var sets: Int
    public var minutes: Int

    public init(date: Date, level: Int, sets: Int, minutes: Int) {
        self.date = date
        self.level = level
        self.sets = sets
        self.minutes = minutes
    }
}

/// One week's totals, in and out of `ConsistencyCalendar.weeklyRecap`.
public struct WeekActivity: Sendable, Hashable {
    public var workouts: Int
    public var sets: Int
    public var volumeKg: Double
    public var durationMinutes: Int
    public var prs: Int

    public init(workouts: Int, sets: Int, volumeKg: Double, durationMinutes: Int, prs: Int) {
        self.workouts = workouts
        self.sets = sets
        self.volumeKg = volumeKg
        self.durationMinutes = durationMinutes
        self.prs = prs
    }
}

/// A week's headline numbers plus week-over-week deltas, for the "Weekly Recap" card and the
/// Sunday-evening recap notification.
public struct WeeklyRecap: Sendable, Hashable {
    public var weekStart: Date
    public var weeklyGoal: Int
    public var workouts: Int
    public var sets: Int
    public var volumeKg: Double
    public var prs: Int
    public var workoutsDelta: Int
    public var setsDelta: Int
    public var prsDelta: Int
    /// Percent change in volume vs. last week, `nil` when last week had zero volume (no baseline
    /// to compare against).
    public var volumeDeltaPercent: Double?

    public init(
        weekStart: Date, weeklyGoal: Int, workouts: Int, sets: Int, volumeKg: Double, prs: Int,
        workoutsDelta: Int, setsDelta: Int, prsDelta: Int, volumeDeltaPercent: Double?
    ) {
        self.weekStart = weekStart
        self.weeklyGoal = weeklyGoal
        self.workouts = workouts
        self.sets = sets
        self.volumeKg = volumeKg
        self.prs = prs
        self.workoutsDelta = workoutsDelta
        self.setsDelta = setsDelta
        self.prsDelta = prsDelta
        self.volumeDeltaPercent = volumeDeltaPercent
    }
}

/// Consistency-heatmap and weekly-recap math, shared by the Progress tab and the reminder
/// notifications (plan.md §6.4). No UI, no persistence — everything here is pure functions over
/// dates the caller already fetched from the store.
public enum ConsistencyCalendar {
    // swiftlint:disable large_tuple
    /// Buckets `workouts` by calendar day inside `[from, to]` (inclusive, one `DayCell` per day
    /// even when nothing happened that day) and assigns each day a 0…4 level.
    ///
    /// Level 0 means no sets. Levels 1–4 are quantile bands of that day's sets relative to the
    /// busiest day anywhere in the range (`maxSets`): ratio < 25% → 1, < 50% → 2, < 75% → 3,
    /// otherwise → 4. A single 3-set day in an otherwise empty range is its own busiest day and
    /// lands at level 4 — the ramp is about relative effort within the window, not an absolute
    /// set count.
    public static func cells(
        workouts: [(date: Date, sets: Int, minutes: Int)], from: Date, to: Date, calendar: Calendar
    ) -> [DayCell] {
        // swiftlint:enable large_tuple
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        guard start <= end else { return [] }

        var byDay: [Date: (sets: Int, minutes: Int)] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.date)
            guard day >= start, day <= end else { continue }
            var totals = byDay[day] ?? (sets: 0, minutes: 0)
            totals.sets += workout.sets
            totals.minutes += workout.minutes
            byDay[day] = totals
        }
        let maxSets = byDay.values.map(\.sets).max() ?? 0

        var result: [DayCell] = []
        var day = start
        while day <= end {
            let totals = byDay[day] ?? (sets: 0, minutes: 0)
            result.append(
                DayCell(date: day, level: level(sets: totals.sets, maxSets: maxSets),
                        sets: totals.sets, minutes: totals.minutes)
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private static func level(sets: Int, maxSets: Int) -> Int {
        guard sets > 0, maxSets > 0 else { return 0 }
        let ratio = Double(sets) / Double(maxSets)
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 0.75 { return 3 }
        return 4
    }

    /// Lays `cells` (assumed sorted or at least covering one contiguous range) into weeks of 7
    /// days, honouring `calendar.firstWeekday`. Each inner array is exactly 7 slots, `nil` where
    /// a day falls outside `cells`' own date range (padding at the start of the first week or the
    /// end of the last).
    public static func monthGrid(cells: [DayCell], calendar: Calendar) -> [[DayCell?]] {
        let dates = cells.map(\.date)
        guard let first = dates.min(), let last = dates.max(),
              let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start else {
            return []
        }
        let byDay = Dictionary(uniqueKeysWithValues: cells.map { (calendar.startOfDay(for: $0.date), $0) })

        var weeks: [[DayCell?]] = []
        var weekStart = firstWeekStart
        while weekStart <= last {
            weeks.append(week(startingAt: weekStart, byDay: byDay, calendar: calendar))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    private static func week(
        startingAt weekStart: Date, byDay: [Date: DayCell], calendar: Calendar
    ) -> [DayCell?] {
        (0..<7).map { offset -> DayCell? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return byDay[calendar.startOfDay(for: day)]
        }
    }

    /// `thisWeek`'s headline numbers plus deltas against `lastWeek`, for the Weekly Recap card and
    /// notification body.
    public static func weeklyRecap(
        thisWeek: WeekActivity, lastWeek: WeekActivity, week: Date, weeklyGoal: Int, calendar: Calendar
    ) -> WeeklyRecap {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: week)?.start ?? week
        return WeeklyRecap(
            weekStart: weekStart, weeklyGoal: weeklyGoal, workouts: thisWeek.workouts, sets: thisWeek.sets,
            volumeKg: thisWeek.volumeKg, prs: thisWeek.prs,
            workoutsDelta: thisWeek.workouts - lastWeek.workouts, setsDelta: thisWeek.sets - lastWeek.sets,
            prsDelta: thisWeek.prs - lastWeek.prs,
            volumeDeltaPercent: volumeDeltaPercent(this: thisWeek.volumeKg, last: lastWeek.volumeKg)
        )
    }

    private static func volumeDeltaPercent(this: Double, last: Double) -> Double? {
        guard last > 0 else { return nil }
        return (this - last) / last * 100
    }

    /// Saturday at `hour:00` in the week containing `now`, if the weekly goal is at risk and still
    /// reachable: some sessions remain (`thisWeekCount < weeklyGoal`) and there are still enough
    /// days left from Saturday through the end of the week to fit them. Returns `nil` when the
    /// goal is already met, or when it no longer is (too many sessions still needed for the days
    /// remaining) — nagging about a goal that can't be hit any more isn't useful.
    public static func streakReminderDate(
        now: Date, weeklyGoal: Int, thisWeekCount: Int, calendar: Calendar, hour: Int = 18
    ) -> Date? {
        guard weeklyGoal > 0, thisWeekCount < weeklyGoal else { return nil }
        let remaining = weeklyGoal - thisWeekCount
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now),
              let saturday = saturday(in: weekInterval, calendar: calendar),
              let weekEnd = calendar.date(byAdding: .day, value: -1, to: weekInterval.end),
              calendar.startOfDay(for: saturday) >= calendar.startOfDay(for: now) else {
            // Saturday's already passed this week (e.g. it's Sunday) — no time left to nudge.
            return nil
        }
        let daysLeft = (calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: saturday), to: calendar.startOfDay(for: weekEnd)
        ).day ?? 0) + 1
        guard remaining <= daysLeft else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: saturday)
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    /// Walks the 7 days of `interval` looking for the one whose Gregorian weekday is Saturday (7)
    /// — independent of `calendar.firstWeekday`, which only shifts where the interval *starts*.
    private static func saturday(in interval: DateInterval, calendar: Calendar) -> Date? {
        var cursor = interval.start
        for _ in 0..<7 {
            if calendar.component(.weekday, from: cursor) == 7 { return cursor }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }
}
