import Foundation

/// Pure sentence-building for the app's Swift Charts views, so VoiceOver gets the trend a
/// sighted user reads off the line instead of a hidden view or a bare chart with unlabeled
/// marks. No SwiftUI here, so it's cheap to unit test.
enum ChartAccessibility {
    /// "Bodyweight, 12 readings from 3 Jan to 14 Sep, first 80 kg, latest 78.5 kg, lowest
    /// 77 kg, highest 81 kg". `format` renders one value with its unit; dates are formatted
    /// day-and-month so the sentence stays short.
    static func trendSummary(
        title: String, dates: [Date], values: [Double], format: (Double) -> String,
        calendar: Calendar = .current
    ) -> String {
        guard let first = values.first, let last = values.last, values.count == dates.count,
              let low = values.min(), let high = values.max(),
              let firstDate = dates.first, let lastDate = dates.last else {
            return "\(title), no readings"
        }
        if values.count == 1 {
            return "\(title), one reading on \(dayMonth(firstDate, calendar: calendar)), \(format(first))"
        }
        var parts = [
            "\(title), \(values.count) readings from \(dayMonth(firstDate, calendar: calendar))"
                + " to \(dayMonth(lastDate, calendar: calendar))",
            "first \(format(first))",
            "latest \(format(last))"
        ]
        if low != high {
            parts.append("lowest \(format(low))")
            parts.append("highest \(format(high))")
        }
        return parts.joined(separator: ", ")
    }

    /// "Weekly volume, 8 weeks, 4 280 kg this week, up from 3 900 kg last week, best 5 100 kg".
    /// For bar charts of one value per period.
    static func periodSummary(
        title: String, periodNoun: String, values: [Double], format: (Double) -> String
    ) -> String {
        guard let latest = values.last, let best = values.max() else { return "\(title), nothing yet" }
        var parts = [
            "\(title), \(values.count) \(periodNoun)",
            "\(format(latest)) this \(singular(periodNoun))"
        ]
        if values.count > 1 {
            let previous = values[values.count - 2]
            let direction = latest > previous ? "up from" : latest < previous ? "down from" : "same as"
            parts.append("\(direction) \(format(previous)) last \(singular(periodNoun))")
        }
        parts.append("best \(format(best))")
        return parts.joined(separator: ", ")
    }

    /// "78.5 kg" — one decimal at most, then the unit word or symbol.
    static func formatter(unit: String) -> (Double) -> String {
        { value in
            let number = value.formatted(.number.precision(.fractionLength(0...1)))
            return unit.isEmpty ? number : "\(number) \(unit)"
        }
    }

    private static func singular(_ noun: String) -> String {
        noun.hasSuffix("s") ? String(noun.dropLast()) : noun
    }

    private static func dayMonth(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(calendar: calendar).day().month(.abbreviated))
    }
}
