import Foundation
import Testing
@testable import GymCore

@Suite("ConsistencyCalendar")
struct ConsistencyTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func day(_ offset: Int, from base: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base) ?? base
    }

    // MARK: - cells

    @Test("a day with no workouts is level 0")
    func emptyDayIsLevelZero() {
        let base = Date()
        let cells = ConsistencyCalendar.cells(
            workouts: [], from: base, to: day(2, from: base), calendar: calendar
        )
        #expect(cells.count == 3)
        #expect(cells.allSatisfy { $0.level == 0 && $0.sets == 0 })
    }

    @Test("levels are quantiles of the busiest day in the range")
    func levelsAreQuantilesOfMax() {
        let base = calendar.startOfDay(for: Date())
        // Busiest day: 20 sets. Others at 25%, 50%, 75%+ of that.
        let workouts: [(date: Date, sets: Int, minutes: Int)] = [
            (day(0, from: base), 20, 60),
            (day(1, from: base), 4, 20), // 20% of max -> level 1
            (day(2, from: base), 10, 30), // 50% of max -> level 3
            (day(3, from: base), 16, 45) // 80% of max -> level 4
        ]
        let cells = ConsistencyCalendar.cells(
            workouts: workouts, from: base, to: day(3, from: base), calendar: calendar
        )
        #expect(cells[0].level == 4) // the busiest day itself
        #expect(cells[1].level == 1)
        #expect(cells[2].level == 3)
        #expect(cells[3].level == 4)
    }

    @Test("multiple workouts on the same day sum their sets and minutes")
    func sameDaySums() {
        let base = calendar.startOfDay(for: Date())
        let workouts: [(date: Date, sets: Int, minutes: Int)] = [
            (base, 5, 20), (base, 3, 10)
        ]
        let cells = ConsistencyCalendar.cells(workouts: workouts, from: base, to: base, calendar: calendar)
        #expect(cells.count == 1)
        #expect(cells[0].sets == 8)
        #expect(cells[0].minutes == 30)
    }

    @Test("workouts outside the range are ignored")
    func outsideRangeIgnored() {
        let base = calendar.startOfDay(for: Date())
        let workouts: [(date: Date, sets: Int, minutes: Int)] = [
            (day(-5, from: base), 10, 30), (base, 4, 15)
        ]
        let cells = ConsistencyCalendar.cells(workouts: workouts, from: base, to: base, calendar: calendar)
        #expect(cells.count == 1)
        #expect(cells[0].sets == 4)
    }

    // MARK: - monthGrid

    @Test("monthGrid pads each week to 7 days, aligned to firstWeekday")
    func monthGridAlignment() {
        // A Wednesday, so the grid must pad Monday and Tuesday with nil.
        var components = DateComponents(year: 2026, month: 9, day: 9) // a Wednesday
        components.timeZone = calendar.timeZone
        let wednesday = calendar.date(from: components) ?? Date()
        let cells = ConsistencyCalendar.cells(
            workouts: [(wednesday, 5, 20)], from: wednesday, to: wednesday, calendar: calendar
        )
        let grid = ConsistencyCalendar.monthGrid(cells: cells, calendar: calendar)
        #expect(grid.count == 1)
        #expect(grid[0].count == 7)
        #expect(grid[0][0] == nil) // Monday: padding
        #expect(grid[0][1] == nil) // Tuesday: padding
        #expect(grid[0][2]?.sets == 5) // Wednesday: the real cell
        #expect(grid[0][3] == nil)
    }

    @Test("monthGrid spans multiple weeks when cells cross a week boundary")
    func monthGridMultipleWeeks() {
        let base = calendar.startOfDay(for: Date())
        let cells = ConsistencyCalendar.cells(
            workouts: [], from: base, to: day(13, from: base), calendar: calendar
        )
        let grid = ConsistencyCalendar.monthGrid(cells: cells, calendar: calendar)
        #expect(grid.count >= 2)
        #expect(grid.allSatisfy { $0.count == 7 })
    }

    // MARK: - weeklyRecap

    @Test("weeklyRecap computes week-over-week deltas")
    func weeklyRecapDeltas() throws {
        let thisWeek = WeekActivity(workouts: 3, sets: 54, volumeKg: 21_420, durationMinutes: 180, prs: 2)
        let lastWeek = WeekActivity(workouts: 2, sets: 50, volumeKg: 19_000, durationMinutes: 150, prs: 0)
        let recap = ConsistencyCalendar.weeklyRecap(
            thisWeek: thisWeek, lastWeek: lastWeek, week: Date(), weeklyGoal: 4, calendar: calendar
        )
        #expect(recap.workouts == 3)
        #expect(recap.workoutsDelta == 1)
        #expect(recap.setsDelta == 4)
        #expect(recap.prsDelta == 2)
        let percent = try #require(recap.volumeDeltaPercent)
        #expect(abs(percent - 12.7) < 0.5)
    }

    @Test("weeklyRecap leaves volumeDeltaPercent nil with no baseline last week")
    func weeklyRecapNoBaseline() {
        let thisWeek = WeekActivity(workouts: 1, sets: 10, volumeKg: 1_000, durationMinutes: 40, prs: 0)
        let lastWeek = WeekActivity(workouts: 0, sets: 0, volumeKg: 0, durationMinutes: 0, prs: 0)
        let recap = ConsistencyCalendar.weeklyRecap(
            thisWeek: thisWeek, lastWeek: lastWeek, week: Date(), weeklyGoal: 4, calendar: calendar
        )
        #expect(recap.volumeDeltaPercent == nil)
    }

    // MARK: - streakReminderDate

    @Test("goal already met: no reminder")
    func reminderNilWhenGoalMet() {
        let now = Date()
        let result = ConsistencyCalendar.streakReminderDate(
            now: now, weeklyGoal: 4, thisWeekCount: 4, calendar: calendar
        )
        #expect(result == nil)
    }

    @Test("goal at risk with sessions still reachable: reminds Saturday at the given hour")
    func reminderScheduledOnSaturday() throws {
        var components = DateComponents(year: 2026, month: 9, day: 9) // Wednesday of that week
        components.timeZone = calendar.timeZone
        let wednesday = calendar.date(from: components) ?? Date()
        // 2 sessions still needed, 2 days left (Sat + Sun) — reachable.
        let result = ConsistencyCalendar.streakReminderDate(
            now: wednesday, weeklyGoal: 4, thisWeekCount: 2, calendar: calendar, hour: 18
        )
        let reminder = try #require(result)
        #expect(calendar.component(.weekday, from: reminder) == 7)
        #expect(calendar.component(.hour, from: reminder) == 18)
    }

    @Test("Saturday has already passed this week (it's Sunday): no reminder")
    func reminderNilWhenSaturdayAlreadyPassed() {
        var components = DateComponents(year: 2026, month: 9, day: 13) // Sunday
        components.timeZone = calendar.timeZone
        let sunday = calendar.date(from: components) ?? Date()
        let result = ConsistencyCalendar.streakReminderDate(
            now: sunday, weeklyGoal: 4, thisWeekCount: 1, calendar: calendar
        )
        #expect(result == nil)
    }

    @Test("too many sessions still needed for the days left: no reminder")
    func reminderNilWhenUnreachable() {
        var components = DateComponents(year: 2026, month: 9, day: 9) // Wednesday
        components.timeZone = calendar.timeZone
        let wednesday = calendar.date(from: components) ?? Date()
        // Only Saturday + Sunday remain (2 days) but 3 sessions are still needed.
        let result = ConsistencyCalendar.streakReminderDate(
            now: wednesday, weeklyGoal: 7, thisWeekCount: 4, calendar: calendar
        )
        #expect(result == nil)
    }
}
