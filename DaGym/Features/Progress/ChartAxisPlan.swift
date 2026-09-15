import Foundation

/// Where an exercise chart puts its x-axis ticks and what it writes under them (plan.md §6.4).
/// Charts' automatic marks over a 3M range fall a few days apart and every one of them prints
/// the month, so the axis reads "Aug Aug Aug Sep Sep". The plan instead picks a stride from the
/// span and a label that changes at every tick: week starts over ≤ 6 weeks ("12 Aug"), month
/// starts over ≤ 6 months ("Sep"), quarter starts beyond that ("Jan ’26"). Pure, so it is tested
/// without a chart.
struct ChartAxisPlan: Equatable {
    enum Granularity: Equatable {
        case weeks, months, quarters
    }

    var granularity: Granularity
    var ticks: [Date]
    /// One label per tick; adjacent repeats are blanked so the same word never prints twice
    /// in a row (a very short span can put two week starts in the same month, for instance).
    var labels: [String]

    static let sixWeeks: TimeInterval = 6 * 7 * 86_400

    /// The plan for points spanning `first...last`. An empty or single-point span gets one tick.
    static func plan(
        from first: Date, to last: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> ChartAxisPlan {
        let granularity = granularity(from: first, to: last, calendar: calendar)
        var ticks = tickDates(from: first, to: last, granularity: granularity, calendar: calendar)
        if ticks.isEmpty { ticks = [first] }
        let formatted = ticks.map { format($0, granularity: granularity, calendar: calendar, locale: locale) }
        return ChartAxisPlan(granularity: granularity, ticks: ticks, labels: dedupingAdjacent(formatted))
    }

    static func granularity(from first: Date, to last: Date, calendar: Calendar) -> Granularity {
        if last.timeIntervalSince(first) <= sixWeeks { return .weeks }
        let months = calendar.dateComponents([.month], from: first, to: last).month ?? 0
        return months < 6 ? .months : .quarters
    }

    /// Period starts inside the span. Quarters snap to Jan/Apr/Jul/Oct so a 1Y axis reads the
    /// same wherever the data begins.
    private static func tickDates(
        from first: Date, to last: Date, granularity: Granularity, calendar: Calendar
    ) -> [Date] {
        let component: Calendar.Component = granularity == .weeks ? .weekOfYear : .month
        let step = granularity == .quarters ? 3 : 1
        guard var cursor = calendar.dateInterval(of: component, for: first)?.start else { return [] }
        if granularity == .quarters {
            let month = calendar.component(.month, from: cursor)
            let back = (month - 1) % 3
            cursor = calendar.date(byAdding: .month, value: -back, to: cursor) ?? cursor
        }
        if cursor < first { cursor = calendar.date(byAdding: component, value: step, to: cursor) ?? last }
        var ticks: [Date] = []
        while cursor <= last {
            ticks.append(cursor)
            guard let next = calendar.date(byAdding: component, value: step, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }

    private static func format(
        _ date: Date, granularity: Granularity, calendar: Calendar, locale: Locale
    ) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch granularity {
        case .weeks:
            return date.formatted(style.day().month(.abbreviated))
        case .months:
            return date.formatted(style.month(.abbreviated))
        case .quarters:
            // January carries the year so a multi-year ALL range stays readable.
            if calendar.component(.month, from: date) == 1 {
                return date.formatted(style.month(.abbreviated).year(.twoDigits))
            }
            return date.formatted(style.month(.abbreviated))
        }
    }

    private static func dedupingAdjacent(_ labels: [String]) -> [String] {
        var result: [String] = []
        var previous: String?
        for label in labels {
            result.append(label == previous ? "" : label)
            if !label.isEmpty { previous = label }
        }
        return result
    }
}
