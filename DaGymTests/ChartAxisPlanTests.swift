import Foundation
import Testing

@testable import DaGym

/// The exercise chart's x-axis: a stride that fits the span, and no label printed twice in a row.
@Suite("Chart axis plan")
struct ChartAxisPlanTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let locale = Locale(identifier: "en_GB")

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10)) ?? Date()
    }

    private func plan(_ first: Date, _ last: Date) -> ChartAxisPlan {
        ChartAxisPlan.plan(from: first, to: last, calendar: Self.calendar, locale: Self.locale)
    }

    @Test("a 3-month span labels month starts once each, never Aug Aug Aug")
    func threeMonthsLabelsEachMonthOnce() {
        let plan = plan(Self.date(2026, 6, 15), Self.date(2026, 9, 14))
        #expect(plan.granularity == .months)
        #expect(plan.labels == ["Jul", "Aug", "Sep"])
        #expect(plan.ticks == [Self.date(2026, 7, 1), Self.date(2026, 8, 1), Self.date(2026, 9, 1)].map {
            Self.calendar.startOfDay(for: $0)
        })
    }

    @Test("up to six weeks labels week starts with the day")
    func shortSpanLabelsWeeks() {
        let plan = plan(Self.date(2026, 8, 5), Self.date(2026, 9, 1))
        #expect(plan.granularity == .weeks)
        #expect(plan.labels == ["10 Aug", "17 Aug", "24 Aug", "31 Aug"])
    }

    @Test("beyond six months labels quarter starts, with the year on January")
    func longSpanLabelsQuarters() {
        let plan = plan(Self.date(2025, 8, 20), Self.date(2026, 9, 14))
        #expect(plan.granularity == .quarters)
        #expect(plan.labels == ["Oct", "Jan 26", "Apr", "Jul"])
    }

    @Test("adjacent duplicate labels are blanked and a one-point span still gets a tick")
    func noAdjacentRepeats() {
        let plans = [
            plan(Self.date(2026, 6, 15), Self.date(2026, 9, 14)),
            plan(Self.date(2026, 8, 5), Self.date(2026, 9, 1)),
            plan(Self.date(2024, 1, 1), Self.date(2026, 9, 14))
        ]
        for plan in plans {
            #expect(plan.ticks.count == plan.labels.count)
            for (lhs, rhs) in zip(plan.labels, plan.labels.dropFirst()) where !lhs.isEmpty {
                #expect(lhs != rhs)
            }
        }
        let single = plan(Self.date(2026, 8, 5), Self.date(2026, 8, 5))
        #expect(single.ticks == [Self.date(2026, 8, 5)])
        #expect(single.labels == ["5 Aug"])
    }
}
