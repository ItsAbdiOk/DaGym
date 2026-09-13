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
}
