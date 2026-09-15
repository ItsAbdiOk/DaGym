import Foundation
import os

/// Weekly workout-streak math, shared by the Home screen and Progress tab.
public enum Streaks {
    /// A week "counts" when at least `weeklyGoal` distinct calendar days in it carried a session
    /// (see `countsPerWeek` — training days, not workouts).
    ///
    /// `current` is the number of consecutive counting weeks ending at either the current week
    /// or the previous week — the current week is still in progress, so not (yet) hitting the
    /// goal this week doesn't by itself break a streak earned in prior weeks. `longest` is the
    /// longest run of counting weeks anywhere in the history. `thisWeekCount` is the number of
    /// training days in the current week, for the weekly-goal progress bar.
    public static func weekly(
        workoutDates: [Date], weeklyGoal: Int, calendar: Calendar, now: Date
    ) -> (current: Int, longest: Int, thisWeekCount: Int) {
        let state = GymCorePerf.signposter.beginInterval("Streaks.weekly")
        defer { GymCorePerf.signposter.endInterval("Streaks.weekly", state) }
        guard weeklyGoal > 0, let nowWeek = WeekKey(now, calendar: calendar) else {
            return (0, 0, 0)
        }
        let countsByWeek = countsPerWeek(workoutDates, calendar: calendar)
        let thisWeekCount = countsByWeek[nowWeek] ?? 0
        let countingWeeks = Set(countsByWeek.filter { $0.value >= weeklyGoal }.keys)
        guard !countingWeeks.isEmpty else { return (0, 0, thisWeekCount) }

        let longest = longestRun(of: countingWeeks, calendar: calendar)
        let current = currentRun(of: countingWeeks, nowWeek: nowWeek, calendar: calendar)
        return (current, longest, thisWeekCount)
    }

    /// One calendar week as `(yearForWeekOfYear, weekOfYear)` — an exact, hashable identity, so
    /// weeks compare by equality instead of by a tolerant `Calendar.isDate(_:equalTo:)` over an
    /// instant. Bucketing on the week's *start instant* used to break in zones whose clocks shift
    /// at midnight (Lord Howe, and every zone on a DST boundary that falls on the first day of
    /// the week): stepping back a week from *now* landed an hour off the bucketed instant, the
    /// exact lookup missed, and the current streak read 0 while the longest still read 12. The
    /// fix was a linear tolerant scan per step — O(run × W) calendar calls, tens of ms on Home for
    /// a two-year history. Keyed weeks make every lookup O(1) with no tolerance needed.
    struct WeekKey: Hashable {
        var year: Int
        var week: Int

        init?(_ date: Date, calendar: Calendar) {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            guard let year = components.yearForWeekOfYear, let week = components.weekOfYear else {
                return nil
            }
            self.year = year
            self.week = week
        }

        /// The key one week earlier / later, stepping through the calendar so the year rolls
        /// over correctly on 52- and 53-week years.
        func previous(calendar: Calendar) -> WeekKey? { shifted(by: -1, calendar: calendar) }
        func next(calendar: Calendar) -> WeekKey? { shifted(by: 1, calendar: calendar) }

        private func shifted(by weeks: Int, calendar: Calendar) -> WeekKey? {
            var components = DateComponents()
            components.yearForWeekOfYear = year
            components.weekOfYear = week
            components.weekday = calendar.firstWeekday
            guard let start = calendar.date(from: components),
                  let shifted = calendar.date(byAdding: .weekOfYear, value: weeks, to: start) else {
                return nil
            }
            return WeekKey(shifted, calendar: calendar)
        }
    }

    /// Training **days** per week, not workouts: a week's count is how many distinct calendar
    /// days carried a session. Two sessions on one Saturday used to count as two toward a goal
    /// of "4 a week", so a lifter who trained twice on two days could hit a four-session goal
    /// having trained on two — and the streak, the weekly goal ring and the consistency
    /// milestone all agreed on the wrong number. `WorkoutStore.consistentWeekCount` counts the
    /// same way.
    private static func countsPerWeek(_ dates: [Date], calendar: Calendar) -> [WeekKey: Int] {
        var daysPerWeek: [WeekKey: Set<Date>] = [:]
        for date in dates {
            guard let key = WeekKey(date, calendar: calendar) else { continue }
            daysPerWeek[key, default: []].insert(calendar.startOfDay(for: date))
        }
        return daysPerWeek.mapValues(\.count)
    }

    /// The longest chain of consecutive keys: each week's predecessor looked up in O(1), so the
    /// whole pass is O(W) calendar steps.
    private static func longestRun(of weeks: Set<WeekKey>, calendar: Calendar) -> Int {
        var longest = 0
        for week in weeks {
            // Only count runs from their first week, so each chain is walked once.
            if let earlier = week.previous(calendar: calendar), weeks.contains(earlier) { continue }
            var runLength = 1
            var cursor = week
            while let next = cursor.next(calendar: calendar), weeks.contains(next) {
                runLength += 1
                cursor = next
            }
            longest = max(longest, runLength)
        }
        return longest
    }

    /// Walks backward from `nowWeek` (or, if this week hasn't counted yet, from the previous
    /// week) while each week still counts — one set lookup per step.
    private static func currentRun(of weeks: Set<WeekKey>, nowWeek: WeekKey, calendar: Calendar) -> Int {
        var cursor = nowWeek
        if !weeks.contains(cursor) {
            guard let previousWeek = cursor.previous(calendar: calendar) else { return 0 }
            cursor = previousWeek
        }
        var run = 0
        while weeks.contains(cursor) {
            run += 1
            guard let previousWeek = cursor.previous(calendar: calendar) else { break }
            cursor = previousWeek
        }
        return run
    }
}
