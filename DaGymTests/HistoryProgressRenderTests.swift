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

    // MARK: - Month calendar load tint

    @Test("a day is tinted lighter to heavier as a share of the month's heaviest day")
    func calendarLoadLevelQuartiles() {
        #expect(MonthCalendarDayCell.loadLevel(loadKg: 0, maxLoadKg: 8000) == 0)
        #expect(MonthCalendarDayCell.loadLevel(loadKg: 500, maxLoadKg: 0) == 0)
        #expect(MonthCalendarDayCell.loadLevel(loadKg: 1000, maxLoadKg: 8000) == 1)
        #expect(MonthCalendarDayCell.loadLevel(loadKg: 3000, maxLoadKg: 8000) == 2)
        #expect(MonthCalendarDayCell.loadLevel(loadKg: 5000, maxLoadKg: 8000) == 3)
        #expect(MonthCalendarDayCell.loadLevel(loadKg: 8000, maxLoadKg: 8000) == 4)
    }

    @Test("the month model carries each trained day's tonnage and the month's heaviest")
    func monthModelLoad() {
        let now = Self.date(14, month: 1)
        var heavy = Self.record("Heavy", day: 5, month: 1)
        heavy.volumeKg = 6000
        let model = MonthCalendarModel(
            month: now, records: [heavy, Self.record("Light", day: 9, month: 1)], schedule: WeeklySchedule(),
            routines: [], calendar: Self.calendar(), now: now
        )
        let byDay = Dictionary(uniqueKeysWithValues: model.days.map { ($0.dayNumber, $0) })
        #expect(byDay[5]?.loadKg == 6000)
        #expect(byDay[9]?.loadKg == 1000)
        #expect(byDay[10]?.loadKg == 0)
        #expect(model.maxLoadKg == 6000)
    }

    // MARK: - Progress hub

    @Test("the coverage split counts muscles at the coach floor as on target, the rest as behind")
    func coverageSplit() {
        let floor = TrainingConstants.coachMinSetsPerMuscleInWindow
        let snapshot = RecoverySnapshot(
            map: [:], perMuscle: [], untrainedMuscles: [],
            detrainedMuscles: [
                MuscleRetention(muscle: .calves, retention: 0.7, lastTrained: Self.date(1, month: 1))
            ]
        )
        let sets: [Muscle: Double] = [.chest: floor + 2, .biceps: floor - 1, .quads: floor]
        let split = ProgressHubSummary.coverageSplit(setsPerMuscle: sets, snapshot: snapshot)
        #expect(split.onTarget == 2)
        // Biceps under the floor, calves trained once but with nothing in the window.
        #expect(split.behind == 2)
        let gap = ProgressHubSummary.widestGap(setsPerMuscle: sets, snapshot: snapshot)
        #expect(gap?.muscle == .calves)
        #expect(gap?.sets == 0)
    }

    @Test("needs work prefers the longest-idle muscle, then the widest coverage gap")
    func needsWorkFallbacks() {
        let now = Self.date(14, month: 1)
        let idle = RecoverySnapshot(
            map: [:], perMuscle: [], untrainedMuscles: [],
            detrainedMuscles: [
                MuscleRetention(muscle: .calves, retention: 0.7, lastTrained: Self.date(5, month: 1))
            ]
        )
        let gap = ProgressHubSummary.CoverageGap(muscle: .biceps, sets: 2)
        #expect(ProgressHubSummary.needsWork(snapshot: idle, gap: gap, now: now)?.muscle == .calves)
        #expect(ProgressHubSummary.needsWork(snapshot: idle, gap: gap, now: now)?.detail == "9 days idle")
        let fresh = RecoverySnapshot(map: [:], perMuscle: [], untrainedMuscles: [])
        let fromGap = ProgressHubSummary.needsWork(snapshot: fresh, gap: gap, now: now)
        #expect(fromGap?.muscle == .biceps)
        #expect(fromGap?.detail == "2 sets in 14 days")
        #expect(ProgressHubSummary.needsWork(snapshot: fresh, gap: nil, now: now) == nil)
    }

    @Test("the average-time tile prints whole minutes")
    func minutesLabel() {
        #expect(ThisWeekStrip.minutesLabel(3_240) == "54m")
        #expect(ThisWeekStrip.minutesLabel(59) == "0m")
    }
}
