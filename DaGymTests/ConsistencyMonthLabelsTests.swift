import Foundation
import GymCore
import Testing

@testable import DaGym

/// The heatmap's month row: one name where each month starts, and never two names on top of
/// each other.
@Suite("Consistency month labels")
struct ConsistencyMonthLabelsTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func grid(from start: Date, days: Int) -> [[DayCell?]] {
        let cells = (0..<days).compactMap { offset -> DayCell? in
            calendar.date(byAdding: .day, value: offset, to: start).map {
                DayCell(date: $0, level: 0, sets: 0, minutes: 0)
            }
        }
        return ConsistencyCalendar.monthGrid(cells: cells, calendar: calendar)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    @Test("each month is named once, on the column holding its first day")
    func oneLabelPerMonthStart() {
        // Mon 2 Mar 2026 → mid-May. Column 4 opens on Mon 30 Mar, so April's name waits for
        // column 5 (Mon 6 Apr); likewise May's for column 9 (Mon 4 May).
        let grid = Self.grid(from: Self.date(2026, 3, 2), days: 75)
        let labels = ConsistencyMonthLabels.labels(for: grid, calendar: Self.calendar)
        #expect(labels == [0: "MAR", 5: "APR", 9: "MAY"])
    }

    @Test("an opening month with fewer than three columns gives way to the next one")
    func crampedOpeningMonthIsDropped() {
        // Starts Mon 21 Sep: September's name would sit on column 0 and October's on column 2
        // (Mon 5 Oct) — 26 pt apart, which two tracked-out names cannot fit — so only OCT stays.
        let grid = Self.grid(from: Self.date(2026, 9, 21), days: 40)
        let labels = ConsistencyMonthLabels.labels(for: grid, calendar: Self.calendar)
        #expect(labels[0] == nil)
        #expect(labels.values.contains("OCT"))
        let columns = labels.keys.sorted()
        for (lhs, rhs) in zip(columns, columns.dropFirst()) {
            #expect(rhs - lhs >= ConsistencyMonthLabels.minimumColumnsBetweenLabels)
        }
    }
}
