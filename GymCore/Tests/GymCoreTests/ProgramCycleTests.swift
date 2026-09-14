import Foundation
import Testing
@testable import GymCore

@Suite("Program cycle")
struct ProgramCycleTests {
    private func calendar(timeZone: String = "UTC", firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? Date()
    }

    /// The headline defect: `dateComponents([.day]) / 7` anchored every week boundary to the
    /// *time of day* the program started, so a Wednesday-21:30 start rolled over mid-Wednesday
    /// evening and put the same Wednesday's 18:00 and 22:00 sessions in different weeks.
    @Test("a mid-week evening start keeps the whole starting week in week 1")
    func midWeekEveningStartHoldsItsWeek() {
        let calendar = calendar()
        // Wednesday 2026-01-07, 21:30.
        let startedAt = date(2026, 1, 7, hour: 21, calendar: calendar)
        let sameWednesdayEarly = date(2026, 1, 7, hour: 18, calendar: calendar)
        let sameWednesdayLate = date(2026, 1, 7, hour: 22, calendar: calendar)
        let sunday = date(2026, 1, 11, hour: 12, calendar: calendar)

        for moment in [sameWednesdayEarly, sameWednesdayLate, sunday] {
            let position = ProgramCycle.position(
                startedAt: startedAt, now: moment, weeks: 4, calendar: calendar
            )
            #expect(position?.week == 1)
        }
        // The next calendar week — Monday the 12th — is week 2, for every hour of it.
        let nextMonday = date(2026, 1, 12, hour: 6, calendar: calendar)
        #expect(
            ProgramCycle.position(startedAt: startedAt, now: nextMonday, weeks: 4, calendar: calendar)?
                .week == 2
        )
    }

    @Test("weekStartsMonday changes where the boundary falls")
    func firstWeekdayMatters() {
        let monday = calendar(firstWeekday: 2)
        let sunday = calendar(firstWeekday: 1)
        // Program started Wednesday the 7th; "now" is Sunday the 11th.
        let startedAt = date(2026, 1, 7, calendar: monday)
        let now = date(2026, 1, 11, calendar: monday)

        // Monday-first: the 11th is still the start week. Sunday-first: it begins a new one.
        #expect(ProgramCycle.weeksElapsed(from: startedAt, to: now, calendar: monday) == 0)
        #expect(ProgramCycle.weeksElapsed(from: startedAt, to: now, calendar: sunday) == 1)
    }

    @Test("flying London to LA doesn't move the week boundary")
    func timezoneChangeDoesNotShiftTheBoundary() {
        let london = calendar(timeZone: "Europe/London")
        let losAngeles = calendar(timeZone: "America/Los_Angeles")
        let startedAt = date(2026, 1, 7, hour: 21, calendar: london)
        // Monday the 12th at 03:00 London — 19:00 on Sunday the 11th in LA.
        let now = date(2026, 1, 12, hour: 3, calendar: london)

        #expect(ProgramCycle.weeksElapsed(from: startedAt, to: now, calendar: london) == 1)
        #expect(ProgramCycle.weeksElapsed(from: startedAt, to: now, calendar: losAngeles) == 0)
        // …and the answer for one calendar never changes with the clock inside a week.
        let laterSameWeek = date(2026, 1, 18, hour: 23, calendar: london)
        #expect(ProgramCycle.weeksElapsed(from: startedAt, to: laterSameWeek, calendar: london) == 1)
    }

    @Test("a DST changeover week still counts as one week")
    func dstWeekCountsOnce() {
        let london = calendar(timeZone: "Europe/London")
        // Spring forward is Sunday 2026-03-29.
        let startedAt = date(2026, 3, 23, calendar: london)
        #expect(
            ProgramCycle.weeksElapsed(
                from: startedAt, to: date(2026, 3, 29, hour: 12, calendar: london), calendar: london
            ) == 0
        )
        #expect(
            ProgramCycle.weeksElapsed(
                from: startedAt, to: date(2026, 3, 30, calendar: london), calendar: london
            ) == 1
        )
        #expect(
            ProgramCycle.weeksElapsed(
                from: startedAt, to: date(2026, 4, 6, calendar: london), calendar: london
            ) == 2
        )
    }

    @Test("the week wraps and the cycle climbs, until the program runs out of cycles")
    func cyclesAreCapped() {
        let calendar = calendar()
        let startedAt = date(2026, 1, 5, calendar: calendar)
        func position(weeksLater: Int) -> (week: Int, cycle: Int)? {
            let now = calendar.date(byAdding: .day, value: weeksLater * 7, to: startedAt) ?? startedAt
            return ProgramCycle.position(startedAt: startedAt, now: now, weeks: 4, calendar: calendar)
        }

        #expect(position(weeksLater: 0)?.week == 1)
        #expect(position(weeksLater: 3)?.week == 4)
        #expect(position(weeksLater: 4)?.week == 1)
        #expect(position(weeksLater: 4)?.cycle == 2)
        #expect(position(weeksLater: 15)?.cycle == ProgramCycle.maxCycles)
        // 16 weeks is four complete 4-week cycles — the program is finished, not on its fifth.
        #expect(position(weeksLater: 16) == nil)
        let sixteenWeeks = calendar.date(byAdding: .day, value: 112, to: startedAt) ?? startedAt
        #expect(
            ProgramCycle.isFinished(
                startedAt: startedAt, now: sixteenWeeks, weeks: 4, calendar: calendar
            )
        )
    }

    @Test("a start date in the future reads as week 1, never a negative week")
    func futureStartIsWeekOne() {
        let calendar = calendar()
        let startedAt = date(2026, 6, 1, calendar: calendar)
        let now = date(2026, 1, 5, calendar: calendar)
        #expect(
            ProgramCycle.position(startedAt: startedAt, now: now, weeks: 4, calendar: calendar)?.week == 1
        )
    }

    @Test("shifted moves whole weeks and never past its limit")
    func shiftClamps() {
        let calendar = calendar()
        let startedAt = date(2026, 1, 5, calendar: calendar)
        let limit = date(2026, 2, 2, calendar: calendar)
        #expect(
            ProgramCycle.shifted(startedAt, byWeeks: 1, notPast: limit, calendar: calendar)
                == date(2026, 1, 12, calendar: calendar)
        )
        #expect(
            ProgramCycle.shifted(startedAt, byWeeks: 10, notPast: limit, calendar: calendar) == limit
        )
        #expect(ProgramCycle.shifted(startedAt, byWeeks: 0, notPast: limit, calendar: calendar) == startedAt)
    }
}
