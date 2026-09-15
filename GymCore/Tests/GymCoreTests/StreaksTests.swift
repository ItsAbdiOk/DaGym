import Foundation
import Testing
@testable import GymCore

@Suite("Streaks")
struct StreaksTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    /// Midday on the given weeks-ago Monday, so it lands cleanly inside that week regardless of
    /// which day `now` itself falls on.
    private func mondayStart(weeksAgo: Int, from now: Date) -> Date {
        let cal = calendar
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart) ?? now
    }

    private func dates(weeksAgo: Int, count: Int, now: Date) -> [Date] {
        let start = mondayStart(weeksAgo: weeksAgo, from: now)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    @Test("no workouts: everything is zero")
    func empty() {
        let now = Date()
        let result = Streaks.weekly(workoutDates: [], weeklyGoal: 4, calendar: calendar, now: now)
        #expect(result.current == 0)
        #expect(result.longest == 0)
        #expect(result.thisWeekCount == 0)
    }

    @Test("three consecutive good weeks (including a full current week) streak to 3")
    func threeConsecutiveWeeks() {
        let now = Date()
        var workouts: [Date] = []
        for weeksAgo in 0..<3 {
            workouts += dates(weeksAgo: weeksAgo, count: 4, now: now)
        }
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: calendar, now: now)
        #expect(result.current == 3)
        #expect(result.longest == 3)
        #expect(result.thisWeekCount == 4)
    }

    @Test("a gap between good weeks resets the current streak but not the longest")
    func gapResets() {
        let now = Date()
        // Good 4 weeks ago and 3 weeks ago (a 2-week run), a gap at 2 weeks ago, then good
        // last week and this week (another run, currently length 2).
        var workouts: [Date] = []
        workouts += dates(weeksAgo: 4, count: 4, now: now)
        workouts += dates(weeksAgo: 3, count: 4, now: now)
        workouts += dates(weeksAgo: 1, count: 4, now: now)
        workouts += dates(weeksAgo: 0, count: 4, now: now)
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: calendar, now: now)
        #expect(result.longest == 2)
        #expect(result.current == 2)
    }

    @Test("an in-progress current week with 1/4 doesn't break last week's streak")
    func inProgressCurrentWeekDoesNotBreakStreak() {
        let now = Date()
        var workouts: [Date] = []
        workouts += dates(weeksAgo: 2, count: 4, now: now)
        workouts += dates(weeksAgo: 1, count: 4, now: now)
        workouts += dates(weeksAgo: 0, count: 1, now: now) // only 1 of 4 so far this week
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: calendar, now: now)
        #expect(result.current == 2)
        #expect(result.thisWeekCount == 1)
    }

    @Test("a fully missed current AND previous week zeroes the current streak")
    func missedTwoWeeksZeroesCurrent() {
        let now = Date()
        var workouts: [Date] = []
        workouts += dates(weeksAgo: 3, count: 4, now: now)
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: calendar, now: now)
        #expect(result.current == 0)
        #expect(result.longest == 1)
    }

    @Test("two sessions on one day are one day toward the weekly goal, not two")
    func twoSessionsInOneDayCountOnce() {
        let now = Date()
        let start = mondayStart(weeksAgo: 0, from: now)
        // Four sessions, but only two calendar days: morning and evening on Monday and Tuesday.
        let hoursFromWeekStart = [8, 19, 32, 43]
        let workouts = hoursFromWeekStart.compactMap {
            calendar.date(byAdding: .hour, value: $0, to: start)
        }
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: calendar, now: now)
        #expect(result.thisWeekCount == 2)
        #expect(result.current == 0)
    }

    @Test("a week with four sessions across four days still counts")
    func fourDistinctDaysCount() {
        let now = Date()
        let workouts = dates(weeksAgo: 0, count: 4, now: now)
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: calendar, now: now)
        #expect(result.thisWeekCount == 4)
        #expect(result.current == 1)
    }

    @Test("current and longest agree across a week boundary in a zone that shifts at midnight")
    func currentAndLongestAgreeAcrossMidnightShiftingZone() {
        // Lord Howe Island's clocks move at 02:00 on the first Sunday of April, and its week (with
        // firstWeekday = 1) starts on that same Sunday — so `dateInterval` and "step back one
        // week from now" land on different instants. `currentRun` compared them exactly and read
        // 0 while `longestRun`, which compares tolerantly, read the full streak.
        var lordHowe = Calendar(identifier: .gregorian)
        lordHowe.firstWeekday = 1 // Sunday
        lordHowe.timeZone = TimeZone(identifier: "Australia/Lord_Howe") ?? .current

        var components = DateComponents(year: 2026, month: 4, day: 8, hour: 12) // Wed after the shift
        components.timeZone = lordHowe.timeZone
        let now = lordHowe.date(from: components) ?? Date()

        func weekDates(weeksAgo: Int, count: Int) -> [Date] {
            let thisWeekStart = lordHowe.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let start = lordHowe.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart) ?? now
            return (0..<count).compactMap {
                lordHowe.date(byAdding: .hour, value: $0 * 24 + 12, to: start)
            }
        }

        var workouts: [Date] = []
        for weeksAgo in 0..<3 { workouts += weekDates(weeksAgo: weeksAgo, count: 4) }
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: lordHowe, now: now)
        #expect(result.longest == 3)
        #expect(result.current == result.longest)
    }

    @Test("a streak spanning the Europe/London spring-forward DST boundary stays intact")
    func streakAcrossDSTBoundary() {
        var london = Calendar(identifier: .gregorian)
        london.firstWeekday = 2 // Monday
        london.timeZone = TimeZone(identifier: "Europe/London") ?? .current

        // 2026's clocks spring forward on the last Sunday of March (the 29th). "now" is the
        // Monday after, so the week ending just before it straddles the transition and the one
        // before that sits entirely ahead of it.
        var components = DateComponents(year: 2026, month: 4, day: 6, hour: 12) // Monday after DST
        components.timeZone = london.timeZone
        let now = london.date(from: components) ?? Date()

        func mondayStart(weeksAgo: Int) -> Date {
            let thisWeekStart = london.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return london.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart) ?? now
        }
        func weekDates(weeksAgo: Int, count: Int) -> [Date] {
            let start = mondayStart(weeksAgo: weeksAgo)
            return (0..<count).compactMap { london.date(byAdding: .day, value: $0, to: start) }
        }

        var workouts: [Date] = []
        workouts += weekDates(weeksAgo: 2, count: 4) // week of Mon 23 Mar, before DST
        workouts += weekDates(weeksAgo: 1, count: 4) // week of Mon 30 Mar, spans the spring-forward

        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: london, now: now)
        // Both weeks count and are consecutive, even though a DST transition falls between them.
        #expect(result.longest == 2)
        #expect(result.current == 2)
    }

    @Test("weeks are keyed by (yearForWeekOfYear, weekOfYear), so a streak crosses the year boundary")
    func streakCrossesYearBoundary() {
        let cal = calendar
        var components = DateComponents(year: 2025, month: 1, day: 8, hour: 12) // Wed in ISO week 2
        components.timeZone = cal.timeZone
        let now = cal.date(from: components) ?? Date()
        var workouts: [Date] = []
        for weeksAgo in 0..<6 { workouts += dates(weeksAgo: weeksAgo, count: 4, now: now) }
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: cal, now: now)
        #expect(result.current == 6)
        #expect(result.longest == 6)
        #expect(Streaks.WeekKey(now, calendar: cal)?.week == 2)
        let lastYear = Streaks.WeekKey(now, calendar: cal)?.previous(calendar: cal)?.previous(calendar: cal)
        #expect(lastYear?.year == 2024)
        #expect(lastYear?.week == 52)
        #expect(lastYear?.next(calendar: cal)?.next(calendar: cal) == Streaks.WeekKey(now, calendar: cal))
    }

    @Test("a two-year history with a long streak is one lookup per week, and the maths still agrees")
    func longHistoryStaysCorrect() {
        let now = Date()
        var workouts: [Date] = []
        for weeksAgo in 0..<104 where weeksAgo != 60 {
            workouts += dates(weeksAgo: weeksAgo, count: 4, now: now)
        }
        let result = Streaks.weekly(workoutDates: workouts, weeklyGoal: 4, calendar: calendar, now: now)
        #expect(result.current == 60)
        #expect(result.longest == 60)
        #expect(result.thisWeekCount == 4)
    }
}
