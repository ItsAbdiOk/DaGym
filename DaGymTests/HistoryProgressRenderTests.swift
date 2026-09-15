import Foundation
import GymCore
import Testing

@testable import DaGym

/// The History/Progress render-path work: week buckets built once per refresh, the heatmap's
/// "Time" ramp fed a precomputed maximum, chart points with unique ids and trend points keyed
/// by date. Each is the pure piece behind a view that used to recompute it on every pass.
@MainActor
@Suite("History & Progress render paths")
struct HistoryProgressRenderTests {
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// 10:00 UTC on the given day of 2026 (or `year`).
    private static func date(_ day: Int, month: Int, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 10
        return calendar().date(from: components) ?? Date()
    }

    private static func record(_ title: String, day: Int, month: Int, year: Int = 2026) -> WorkoutRecord {
        WorkoutRecord(
            title: title, date: date(day, month: month, year: year), durationMinutes: 45, volumeKg: 1000,
            sets: 10
        )
    }

    // MARK: - HistoryView.weekGroups

    @Test("records bucket into This Week, Last Week and older months, newest first")
    func weekGroupsBucketByTrainingWeek() {
        // Wednesday 14 Jan 2026; the Monday-first week runs 12–18 Jan.
        let now = Self.date(14, month: 1)
        let records = [
            Self.record("Old", day: 3, month: 12, year: 2025),
            Self.record("Mon", day: 12, month: 1),
            Self.record("Last", day: 9, month: 1),
            Self.record("Tue", day: 13, month: 1),
            Self.record("Older", day: 20, month: 12, year: 2025)
        ]
        let groups = HistoryView.weekGroups(records: records, now: now, calendar: Self.calendar())

        #expect(groups.map(\.label) == ["This Week", "Last Week", "DECEMBER"])
        #expect(groups[0].records.map(\.title) == ["Tue", "Mon"])
        #expect(groups[1].records.map(\.title) == ["Last"])
        #expect(groups[2].records.map(\.title) == ["Older", "Old"])
        #expect(groups.map(\.id) == groups.map(\.label))
    }

    @Test("the week start moves a Sunday session between This Week and Last Week")
    func weekGroupsFollowFirstWeekday() {
        // Monday 12 Jan; Sunday 11 Jan is last week Monday-first, this week Sunday-first.
        let now = Self.date(12, month: 1)
        let records = [Self.record("Sun", day: 11, month: 1)]
        var sundayFirst = Self.calendar()
        sundayFirst.firstWeekday = 1

        let mondayFirst = HistoryView.weekGroups(records: records, now: now, calendar: Self.calendar())
        let sundayFirstGroups = HistoryView.weekGroups(records: records, now: now, calendar: sundayFirst)
        #expect(mondayFirst.map(\.label) == ["Last Week"])
        #expect(sundayFirstGroups.map(\.label) == ["This Week"])
    }

    @Test("no records means no groups")
    func weekGroupsEmpty() {
        #expect(HistoryView.weekGroups(records: [], now: Date(), calendar: Self.calendar()).isEmpty)
    }

    // MARK: - HeatmapCard

    @Test("the Time ramp quantises minutes against the busiest day")
    func timeLevelQuartiles() {
        #expect(HeatmapCard.timeLevel(minutes: 0, maxMinutes: 80) == 0)
        #expect(HeatmapCard.timeLevel(minutes: 10, maxMinutes: 0) == 0)
        #expect(HeatmapCard.timeLevel(minutes: 10, maxMinutes: 80) == 1)
        #expect(HeatmapCard.timeLevel(minutes: 20, maxMinutes: 80) == 2)
        #expect(HeatmapCard.timeLevel(minutes: 40, maxMinutes: 80) == 3)
        #expect(HeatmapCard.timeLevel(minutes: 60, maxMinutes: 80) == 4)
        #expect(HeatmapCard.timeLevel(minutes: 80, maxMinutes: 80) == 4)
    }

    @Test("the tapped-day footnote reads day, sets and minutes")
    func footnoteFormat() {
        let cell = DayCell(date: Self.date(14, month: 1), level: 2, sets: 12, minutes: 55)
        let footnote = HeatmapCard.footnote(for: cell)
        #expect(footnote.hasSuffix(" · 12 sets · 55 min"))
        #expect(footnote.contains("14"))
    }

    // MARK: - ChartPoint

    @Test("two sessions on one day get distinct, order-stable ids and their own RPE")
    func chartPointIdsAreUniquePerPoint() {
        let day = Self.date(14, month: 1)
        let later = day.addingTimeInterval(3 * 3600)
        let points = ChartPoint.series(
            [(date: day, value: 100), (date: later, value: 105), (date: day, value: 90)],
            rpe: [day: 8]
        )
        #expect(points.map(\.id) == [0, 1, 2])
        #expect(Set(points.map(\.id)).count == 3)
        #expect(points.map(\.rpe) == [8, nil, 8])
        #expect(ChartPoint.series([(date: day, value: 1)]) == ChartPoint.series([(date: day, value: 1)]))
    }

    // MARK: - TrendChartView.Point

    @Test("trend points are identified by their date, so a rebuild keeps identity")
    func trendPointIdentity() {
        let date = Self.date(14, month: 1)
        let first = TrendChartView.Point(date: date, value: 80)
        let second = TrendChartView.Point(date: date, value: 80.5)
        #expect(first.id == date)
        #expect(first.id == second.id)
    }
}
