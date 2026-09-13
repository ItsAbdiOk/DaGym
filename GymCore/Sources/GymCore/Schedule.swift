import Foundation

/// A day of the week, numbered to match `Calendar.component(.weekday, from:)`
/// (Sunday = 1 … Saturday = 7) so lookups never need a translation table.
public enum Weekday: Int, CaseIterable, Codable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    /// `self` in Monday-first or Sunday-first week order, for a 7-row schedule list.
    public static func ordered(mondayFirst: Bool) -> [Weekday] {
        mondayFirst
            ? [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            : [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    }

    public var shortLabel: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    public var displayName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }
}

/// A "yyyy-MM-dd" calendar-day key, used to address `WeeklySchedule.overrides`
/// without pulling in a locale-sensitive `DateFormatter` (which also isn't
/// safe to share across threads). Calendar-component based, so it is stable
/// regardless of time-of-day.
public enum DateKey {
    public static func string(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }
}

/// A recurring routine-per-weekday plan with per-date reschedules. `overrides`
/// wins over `days` for a given calendar day; an override value of `nil`
/// (present key, `nil` payload) marks that date as a rest day even if a
/// routine would normally land there.
public struct WeeklySchedule: Codable, Hashable, Sendable {
    public var days: [Weekday: UUID]
    /// Keyed by `DateKey.string(for:calendar:)`. `nil` = explicit rest day.
    public var overrides: [String: UUID?]

    public init(days: [Weekday: UUID] = [:], overrides: [String: UUID?] = [:]) {
        self.days = days
        self.overrides = overrides
    }

    /// The routine planned for `date`, if any. An override (including an
    /// explicit rest override) always wins over the recurring weekday plan.
    public func routineID(on date: Date, calendar: Calendar = .current) -> UUID? {
        let key = DateKey.string(for: date, calendar: calendar)
        if let override = overrides[key] {
            return override
        }
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) else { return nil }
        return days[weekday]
    }

    /// The next planned session strictly after `date`, searching up to
    /// `limit` days ahead and skipping rest days. `nil` if nothing is
    /// planned within the window.
    public func nextSession(
        after date: Date, calendar: Calendar = .current, limit: Int = 14
    ) -> (date: Date, routineID: UUID)? {
        var cursor = date
        for _ in 0..<limit {
            guard let candidate = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = candidate
            if let routineID = routineID(on: candidate, calendar: calendar) {
                return (candidate, routineID)
            }
        }
        return nil
    }

    /// Every planned session from `startDate` for `days` calendar days
    /// (inclusive of `startDate`), in date order. Rest days are omitted.
    /// Feeds calendar sync, which upserts one event per entry.
    public func plannedSessions(
        from startDate: Date, days: Int, calendar: Calendar = .current
    ) -> [(date: Date, routineID: UUID)] {
        (0..<max(0, days)).compactMap { offset -> (date: Date, routineID: UUID)? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            guard let routineID = routineID(on: date, calendar: calendar) else { return nil }
            return (date, routineID)
        }
    }

    /// Reschedules `date` to `routineID` (or to rest, when `nil`), writing an
    /// override so the date no longer follows the recurring weekday plan.
    public mutating func moved(date: Date, to routineID: UUID?, calendar: Calendar = .current) {
        let key = DateKey.string(for: date, calendar: calendar)
        overrides[key] = routineID
    }
}
