import Foundation

/// Weekly workout-streak math, shared by the Home screen and Progress tab.
public enum Streaks {
    // swiftlint:disable large_tuple
    /// A week "counts" when it has at least `weeklyGoal` workouts.
    ///
    /// `current` is the number of consecutive counting weeks ending at either the current week
    /// or the previous week — the current week is still in progress, so not (yet) hitting the
    /// goal this week doesn't by itself break a streak earned in prior weeks. `longest` is the
    /// longest run of counting weeks anywhere in the history. `thisWeekCount` is the raw count
    /// of workouts in the current week, for the weekly-goal progress bar.
    public static func weekly(
        workoutDates: [Date], weeklyGoal: Int, calendar: Calendar, now: Date
    ) -> (current: Int, longest: Int, thisWeekCount: Int) {
        // swiftlint:enable large_tuple
        guard weeklyGoal > 0,
              let nowWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return (0, 0, 0)
        }
        let countsByWeek = countsPerWeek(workoutDates, calendar: calendar)
        let thisWeekCount = countsByWeek[nowWeekStart] ?? 0
        let countingWeeks = Set(countsByWeek.filter { $0.value >= weeklyGoal }.keys)
        guard !countingWeeks.isEmpty else { return (0, 0, thisWeekCount) }

        let longest = longestRun(of: countingWeeks, calendar: calendar)
        let current = currentRun(of: countingWeeks, nowWeekStart: nowWeekStart, calendar: calendar)
        return (current, longest, thisWeekCount)
    }

    /// Training **days** per week, not workouts: a week's count is how many distinct calendar
    /// days carried a session. Two sessions on one Saturday used to count as two toward a goal
    /// of "4 a week", so a lifter who trained twice on two days could hit a four-session goal
    /// having trained on two — and the streak, the weekly goal ring and the consistency
    /// milestone all agreed on the wrong number. `WorkoutStore.consistentWeekCount` counts the
    /// same way.
    private static func countsPerWeek(_ dates: [Date], calendar: Calendar) -> [Date: Int] {
        var daysPerWeek: [Date: Set<Date>] = [:]
        for date in dates {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            daysPerWeek[start, default: []].insert(calendar.startOfDay(for: date))
        }
        return daysPerWeek.mapValues(\.count)
    }

    private static func longestRun(of weeks: Set<Date>, calendar: Calendar) -> Int {
        let sorted = weeks.sorted()
        var longest = 0
        var runLength = 0
        var previous: Date?
        for week in sorted {
            if let previous, isOneWeekLater(previous, week, calendar: calendar) {
                runLength += 1
            } else {
                runLength = 1
            }
            longest = max(longest, runLength)
            previous = week
        }
        return longest
    }

    /// Walks backward from `nowWeekStart` (or, if this week hasn't counted yet, from the
    /// previous week) while each week still counts.
    ///
    /// Weeks are matched with the same tolerant `.weekOfYear` comparison `longestRun` uses, not
    /// by exact `Date` equality. The counting weeks are bucketed by whatever instant
    /// `dateInterval` returned when the workouts were read; stepping back a week from *now* in a
    /// zone whose clocks shift at midnight (Lord Howe, and every zone on a DST boundary that
    /// falls on the first day of the week) lands an hour off that instant, `Set.contains` missed,
    /// and the current streak read 0 while the longest still read 12.
    private static func currentRun(of weeks: Set<Date>, nowWeekStart: Date, calendar: Calendar) -> Int {
        func counts(_ week: Date) -> Bool {
            weeks.contains { calendar.isDate($0, equalTo: week, toGranularity: .weekOfYear) }
        }
        var cursor = nowWeekStart
        if !counts(cursor) {
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else {
                return 0
            }
            cursor = previousWeek
        }
        var run = 0
        while counts(cursor) {
            run += 1
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else {
                break
            }
            cursor = previousWeek
        }
        return run
    }

    private static func isOneWeekLater(_ earlier: Date, _ later: Date, calendar: Calendar) -> Bool {
        guard let expected = calendar.date(byAdding: .weekOfYear, value: 1, to: earlier) else { return false }
        return calendar.isDate(expected, equalTo: later, toGranularity: .weekOfYear)
    }
}
