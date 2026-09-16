import Foundation

/// The next planned session as a small screen (the watch face, a complication, the wrist's
/// Home) shows it: no ids, no exercises, already labelled. Built once by the app layer from
/// the schedule and the routine list; `Codable` so it can ride inside a cached payload that an
/// older reader must still decode (every field is plain data — add fields as optionals).
public struct NextPlannedSession: Codable, Hashable, Sendable {
    public var routineName: String
    /// "Today", "Tomorrow" or a short weekday ("Wed") — see `dayLabel(for:now:calendar:)`.
    public var dayLabel: String
    /// The planned day (the schedule's date, at the app layer's chosen start hour).
    public var date: Date
    public var exerciseCount: Int
    public var estimatedMinutes: Int

    public init(
        routineName: String, dayLabel: String, date: Date, exerciseCount: Int, estimatedMinutes: Int
    ) {
        self.routineName = routineName
        self.dayLabel = dayLabel
        self.date = date
        self.exerciseCount = exerciseCount
        self.estimatedMinutes = estimatedMinutes
    }

    /// "Today" / "Tomorrow" for the two days a lifter reads at a glance, else the weekday
    /// from `Weekday.shortLabel` — the same three-letter forms the schedule screen uses, so
    /// the face and the phone agree. Pure over `(date, now, calendar)`.
    public static func dayLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        if day == today { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), day == tomorrow {
            return "Tomorrow"
        }
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
        return weekday.shortLabel
    }

    /// "Tomorrow · 48 min" — the second line under the routine name on the watch.
    public var detailLine: String { "\(dayLabel) · \(estimatedMinutes) min" }
}

/// The one-line "Coach says" tip a wrist-sized surface can show: the top card's title from
/// the on-device rules coach, trimmed to fit. No network, no model — if `CoachEngine` has
/// nothing to say, neither does this.
public enum CoachGlance {
    /// The longest line a complication row or the watch's secondary text takes.
    public static let maxLineLength = 60

    /// The most important card's title, or nil when the coach has no cards. `cards` is the
    /// engine's already-sorted output (most important first), so the first one wins.
    public static func line(from cards: [CoachCard], maxLength: Int = maxLineLength) -> String? {
        guard let card = cards.first else { return nil }
        return trimmed(card.title, to: maxLength)
    }

    /// `text` cut to `maxLength` characters with an ellipsis, on a word boundary when one is
    /// close enough that the cut doesn't lose most of the line. Whitespace is collapsed first:
    /// a card title never has a newline, but the phone's chat proposals can.
    public static func trimmed(_ text: String, to maxLength: Int) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > maxLength, maxLength > 1 else { return collapsed }
        let hard = collapsed.prefix(maxLength - 1)
        if let space = hard.lastIndex(of: " "),
           hard.distance(from: hard.startIndex, to: space) >= maxLength / 2 {
            return String(hard[..<space]) + "…"
        }
        return String(hard) + "…"
    }
}
