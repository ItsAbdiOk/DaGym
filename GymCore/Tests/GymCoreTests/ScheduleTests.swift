import Foundation
import Testing
@testable import GymCore

@Suite("Weekly schedule")
struct ScheduleTests {
    private static func makeCalendar(mondayFirst: Bool) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = mondayFirst ? 2 : 1
        return calendar
    }

    /// Monday 2026-01-05, a fixed reference date.
    private static func referenceMonday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        return makeCalendar(mondayFirst: true).date(from: components) ?? Date()
    }

    @Test("weekday raw values match Calendar's numbering regardless of week start")
    func weekdayMapping() {
        let mondayFirstCalendar = Self.makeCalendar(mondayFirst: true)
        let sundayFirstCalendar = Self.makeCalendar(mondayFirst: false)
        let monday = Self.referenceMonday()
        let sunday = mondayFirstCalendar.date(byAdding: .day, value: 6, to: monday) ?? monday

        #expect(mondayFirstCalendar.component(.weekday, from: monday) == Weekday.monday.rawValue)
        #expect(sundayFirstCalendar.component(.weekday, from: sunday) == Weekday.sunday.rawValue)
        #expect(Weekday.ordered(mondayFirst: true).first == .monday)
        #expect(Weekday.ordered(mondayFirst: true).last == .sunday)
        #expect(Weekday.ordered(mondayFirst: false).first == .sunday)
    }

    @Test("an override wins over the recurring weekday plan, including a rest override")
    func overridePrecedence() {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let pushA = UUID()
        let pullB = UUID()
        let monday = Self.referenceMonday()
        var schedule = WeeklySchedule(days: [.monday: pushA])

        #expect(schedule.routineID(on: monday, calendar: calendar) == pushA)

        schedule.moved(date: monday, to: pullB, calendar: calendar)
        #expect(schedule.routineID(on: monday, calendar: calendar) == pullB)

        schedule.moved(date: monday, to: nil, calendar: calendar)
        #expect(schedule.routineID(on: monday, calendar: calendar) == nil)
    }

    @Test("next session skips rest days and returns the following planned date")
    func nextSessionSkipsRestDays() {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let pushA = UUID()
        let legs = UUID()
        let monday = Self.referenceMonday()
        // Monday = Push A, Tuesday = rest (no entry), Wednesday = Legs.
        let schedule = WeeklySchedule(days: [.monday: pushA, .wednesday: legs])

        let next = schedule.nextSession(after: monday, calendar: calendar)
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)

        #expect(next?.routineID == legs)
        if let wednesday, let nextDate = next?.date {
            #expect(calendar.isDate(nextDate, inSameDayAs: wednesday))
        } else {
            Issue.record("expected both dates to resolve")
        }
    }

    @Test("a rescheduled session appears on its new date and not the original one")
    func movedSessionRelocates() {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let pushA = UUID()
        let monday = Self.referenceMonday()
        let thursday = calendar.date(byAdding: .day, value: 3, to: monday) ?? monday
        var schedule = WeeklySchedule(days: [.monday: pushA])

        schedule.moved(date: monday, to: nil, calendar: calendar)
        schedule.moved(date: thursday, to: pushA, calendar: calendar)

        let sessions = schedule.plannedSessions(from: monday, days: 7, calendar: calendar)
        let dates = sessions.map { $0.routineID }

        #expect(schedule.routineID(on: monday, calendar: calendar) == nil)
        #expect(schedule.routineID(on: thursday, calendar: calendar) == pushA)
        #expect(dates == [pushA])
    }

    @Test("planned sessions omit rest days and cover the requested window")
    func plannedSessionsWindow() {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let pushA = UUID()
        let pullB = UUID()
        let monday = Self.referenceMonday()
        let schedule = WeeklySchedule(days: [.monday: pushA, .thursday: pullB])

        let sessions = schedule.plannedSessions(from: monday, days: 7, calendar: calendar)
        #expect(sessions.count == 2)
        #expect(sessions.map(\.routineID) == [pushA, pullB])
    }

    @Test("a day with more than one routine contributes one planned session per routine")
    func plannedSessionsExpandMultiRoutineDays() {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let pushA = UUID()
        let arms = UUID()
        let monday = Self.referenceMonday()
        var schedule = WeeklySchedule()
        schedule.addRoutine(pushA, to: .monday)
        schedule.addRoutine(arms, to: .monday)

        let sessions = schedule.plannedSessions(from: monday, days: 1, calendar: calendar)
        #expect(sessions.count == 2)
        #expect(sessions.map(\.routineID) == [pushA, arms])
        #expect(sessions.allSatisfy { calendar.isDate($0.date, inSameDayAs: monday) })
    }

    @Test("DateKey round trips through Calendar components")
    func dateKeyRoundTrip() {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let monday = Self.referenceMonday()
        let key = DateKey.string(for: monday, calendar: calendar)
        #expect(key == "2026-01-05")
        let decoded = DateKey.date(from: key, calendar: calendar)
        if let decoded {
            #expect(calendar.isDate(decoded, inSameDayAs: monday))
        } else {
            Issue.record("expected DateKey.date(from:) to parse its own output")
        }
    }
    @Test("a day holds an ordered routine list; the single-routine views read its first entry")
    func multipleRoutinesPerDay() {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let pushA = UUID()
        let arms = UUID()
        let monday = Self.referenceMonday()
        var schedule = WeeklySchedule()

        schedule.addRoutine(pushA, to: .monday)
        schedule.addRoutine(arms, to: .monday)
        schedule.addRoutine(arms, to: .monday)
        #expect(schedule.routineIDs(on: monday, calendar: calendar) == [pushA, arms])
        #expect(schedule.routineID(on: monday, calendar: calendar) == pushA)
        #expect(schedule.days[.monday] == pushA)

        // A legacy-style write that doesn't change the first routine keeps the whole list …
        schedule.days[.wednesday] = arms
        #expect(schedule.routineIDs(on: monday, calendar: calendar) == [pushA, arms])
        // … while changing the first routine replaces the day.
        schedule.days[.monday] = arms
        #expect(schedule.routineIDs(on: monday, calendar: calendar) == [arms])

        schedule.removeRoutine(arms, from: .monday)
        #expect(schedule.routineIDs(on: monday, calendar: calendar).isEmpty)
        #expect(schedule.dayRoutines[.monday] == nil)
        #expect(schedule.days[.monday] == nil)
    }

    @Test("a date can be moved onto several routines, and rescheduled dates are flagged")
    func multiRoutineOverride() {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let pushA = UUID()
        let arms = UUID()
        let monday = Self.referenceMonday()
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday) ?? monday
        var schedule = WeeklySchedule(dayRoutines: [.monday: [pushA, arms]])

        schedule.moved(date: monday, toRoutines: [], calendar: calendar)
        schedule.moved(date: tuesday, toRoutines: [pushA, arms], calendar: calendar)
        #expect(schedule.routineIDs(on: monday, calendar: calendar).isEmpty)
        #expect(schedule.routineIDs(on: tuesday, calendar: calendar) == [pushA, arms])
        #expect(schedule.isRescheduled(monday, calendar: calendar))
        #expect(schedule.isRescheduled(tuesday, calendar: calendar))
        #expect(schedule.overrides["2026-01-05"] == .some(nil))
        #expect(schedule.overrides["2026-01-06"] == pushA)
    }

    @Test("single-routine JSON saved before lists existed still decodes, and lists round-trip")
    func legacyDecodingAndRoundTrip() throws {
        let calendar = Self.makeCalendar(mondayFirst: true)
        let pushA = UUID()
        let arms = UUID()
        let monday = Self.referenceMonday()
        let legacy = """
        {"days":[2,"\(pushA.uuidString)"],"overrides":{"2026-01-06":null,"2026-01-07":"\(arms.uuidString)"}}
        """
        let decoded = try JSONDecoder().decode(WeeklySchedule.self, from: Data(legacy.utf8))
        #expect(decoded.routineIDs(on: monday, calendar: calendar) == [pushA])
        #expect(decoded.dateOverrides["2026-01-06"]?.isEmpty == true)
        #expect(decoded.dateOverrides["2026-01-07"] == [arms])
        let expected = WeeklySchedule(
            days: [.monday: pushA], overrides: ["2026-01-06": nil, "2026-01-07": arms]
        )
        #expect(decoded == expected)

        var lists = decoded
        lists.addRoutine(arms, to: .monday)
        let data = try JSONEncoder().encode(lists)
        let again = try JSONDecoder().decode(WeeklySchedule.self, from: data)
        #expect(again == lists)
        #expect(again.routineIDs(on: monday, calendar: calendar) == [pushA, arms])
    }
}
