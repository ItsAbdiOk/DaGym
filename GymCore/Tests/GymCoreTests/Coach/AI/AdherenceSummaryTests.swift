import Foundation
import Testing
@testable import GymCore

@Suite("AdherenceSummary")
struct AdherenceSummaryTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// Wednesday 15 January 2025, mid-afternoon.
    private static let now = Date(timeIntervalSince1970: 1_736_949_600)
    private static let routineID = UUID()

    private static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: now) ?? now
    }

    @Test("a trailing window of N × 7 days counts planned days and the ones actually trained")
    func plannedVersusKept() {
        let schedule = WeeklySchedule(days: [.monday: Self.routineID, .wednesday: Self.routineID])
        // Today (Wed), Monday two days ago, and last Wednesday — but not last Monday.
        let trained = [Self.day(0), Self.day(2), Self.day(7)]
        let summary = AdherenceSummary.over(
            weeks: 2, schedule: schedule, loggedWorkoutDates: trained, now: Self.now, calendar: Self.calendar
        )
        #expect(summary.weeks == 2)
        #expect(summary.planned == 4)
        #expect(summary.kept == 3)
        #expect(summary.percent == 75)
    }

    @Test("an unplanned day earns no credit; a planned day counts once however many sessions")
    func unplannedDaysAndDuplicatesIgnored() {
        let schedule = WeeklySchedule(days: [.wednesday: Self.routineID])
        let trained = [Self.day(1), Self.day(0), Self.day(0).addingTimeInterval(3_600)]
        let summary = AdherenceSummary.over(
            weeks: 1, schedule: schedule, loggedWorkoutDates: trained, now: Self.now, calendar: Self.calendar
        )
        #expect(summary.planned == 1)
        #expect(summary.kept == 1)
        #expect(summary.percent == 100)
    }

    @Test("a date override plans (or rests) a specific day inside the window")
    func overridesApply() {
        let restToday = DateKey.string(for: Self.now, calendar: Self.calendar)
        let schedule = WeeklySchedule(days: [.wednesday: Self.routineID], overrides: [restToday: nil])
        let summary = AdherenceSummary.over(
            weeks: 1, schedule: schedule, loggedWorkoutDates: [Self.day(0)], now: Self.now,
            calendar: Self.calendar
        )
        #expect(summary.planned == 0)
        #expect(summary.kept == 0)
        #expect(summary.percent == nil)
    }

    @Test("percent rounds to the nearest whole number")
    func percentRounds() {
        #expect(AdherenceSummary(planned: 3, kept: 2, weeks: 1).percent == 67)
        #expect(AdherenceSummary(planned: 8, kept: 1, weeks: 1).percent == 13)
        #expect(AdherenceSummary(planned: 0, kept: 0, weeks: 4).percent == nil)
    }
}
