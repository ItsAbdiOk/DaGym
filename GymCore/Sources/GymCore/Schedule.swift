import Foundation

/// A day of the week, numbered to match `Calendar.component(.weekday, from:)`
/// (Sunday = 1 … Saturday = 7) so lookups never need a translation table.
public enum Weekday: Int, CaseIterable, Codable, Hashable, Sendable {
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

/// A recurring routines-per-weekday plan with per-date reschedules. Each day
/// holds an ordered list of routines (a "Push + Arms" day merges them in
/// order when started). `dateOverrides` wins over `dayRoutines` for a given
/// calendar day; an override with an empty list marks that date as a rest
/// day even if routines would normally land there.
///
/// `days` / `overrides` are the original single-routine views of the same
/// data: reading gives the first routine, writing replaces the day's list.
public struct WeeklySchedule: Codable, Hashable, Sendable {
    public var dayRoutines: [Weekday: [UUID]]
    /// Keyed by `DateKey.string(for:calendar:)`. Empty list = explicit rest day.
    public var dateOverrides: [String: [UUID]]

    public init(dayRoutines: [Weekday: [UUID]] = [:], dateOverrides: [String: [UUID]] = [:]) {
        self.dayRoutines = dayRoutines.filter { !$0.value.isEmpty }
        self.dateOverrides = dateOverrides
    }

    public init(days: [Weekday: UUID], overrides: [String: UUID?] = [:]) {
        self.init(
            dayRoutines: days.mapValues { [$0] },
            dateOverrides: overrides.mapValues { $0.map { [$0] } ?? [] }
        )
    }

    /// First routine per weekday. Setting replaces that day's whole list (`nil` clears it).
    public var days: [Weekday: UUID] {
        get { dayRoutines.compactMapValues(\.first) }
        set {
            dayRoutines = Self.merged(newValue.mapValues { [$0] }, into: dayRoutines)
        }
    }

    /// First routine per override date; a present key with `nil` is a rest override.
    /// Setting replaces that date's whole list.
    public var overrides: [String: UUID?] {
        get { dateOverrides.mapValues(\.first) }
        set {
            dateOverrides = Self.merged(newValue.mapValues { $0.map { [$0] } ?? [] }, into: dateOverrides)
        }
    }

    /// Applies a single-routine edit to the list-valued storage: keys that vanished are
    /// dropped, keys whose first routine is unchanged keep their full list, anything else has
    /// only its *first* entry replaced so the rest of a multi-routine day survives.
    ///
    /// Replacing the whole list here is what made a "Push A + Arms" day lose "Arms" every time
    /// something re-pointed the day's first routine through the single-routine `days` view
    /// (`WorkoutStore.dedupeRoutines()` does exactly that when a starter routine folds).
    private static func merged<Key: Hashable>(
        _ singles: [Key: [UUID]], into lists: [Key: [UUID]]
    ) -> [Key: [UUID]] {
        singles.reduce(into: [:]) { result, pair in
            let existing = lists[pair.key] ?? []
            if existing.first == pair.value.first {
                result[pair.key] = existing
            } else if let replacement = pair.value.first, existing.count > 1 {
                // The replacement may already be planned later in the same day; keep it once.
                result[pair.key] = [replacement] + existing.dropFirst().filter { $0 != replacement }
            } else {
                result[pair.key] = pair.value
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case dayRoutines, dateOverrides, days, overrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.dayRoutines) || container.contains(.dateOverrides) {
            let routines = try container.decodeIfPresent([Weekday: [UUID]].self, forKey: .dayRoutines)
            let overrides = try container.decodeIfPresent([String: [UUID]].self, forKey: .dateOverrides)
            self.init(dayRoutines: routines ?? [:], dateOverrides: overrides ?? [:])
        } else {
            let days = try container.decodeIfPresent([Weekday: UUID].self, forKey: .days)
            let overrides = try container.decodeIfPresent([String: UUID?].self, forKey: .overrides)
            self.init(days: days ?? [:], overrides: overrides ?? [:])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dayRoutines, forKey: .dayRoutines)
        try container.encode(dateOverrides, forKey: .dateOverrides)
    }

    /// Every routine planned for `date`, in the order they should be merged
    /// when the day is started. Empty on a rest day. An override (including
    /// an explicit rest override) always wins over the recurring weekday plan.
    public func routineIDs(on date: Date, calendar: Calendar = .current) -> [UUID] {
        let key = DateKey.string(for: date, calendar: calendar)
        if let override = dateOverrides[key] {
            return override
        }
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) else { return [] }
        return dayRoutines[weekday] ?? []
    }

    /// The first routine planned for `date`, if any.
    public func routineID(on date: Date, calendar: Calendar = .current) -> UUID? {
        routineIDs(on: date, calendar: calendar).first
    }

    /// Whether `date` has been rescheduled away from the recurring plan (moved
    /// onto, moved off, or explicitly rested).
    public func isRescheduled(_ date: Date, calendar: Calendar = .current) -> Bool {
        dateOverrides[DateKey.string(for: date, calendar: calendar)] != nil
    }

    /// The next planned session strictly after `date`, searching up to
    /// `limit` days ahead and skipping rest days. `nil` if nothing is
    /// planned within the window. `routineID` is the day's first routine.
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
    /// (inclusive of `startDate`), in date order. Rest days are omitted. A day with more than
    /// one routine planned produces one entry per routine, in that day's merge order — calendar
    /// sync upserts one event per entry, so a "Push A + Arms" day gets two events, not one.
    public func plannedSessions(
        from startDate: Date, days: Int, calendar: Calendar = .current
    ) -> [(date: Date, routineID: UUID)] {
        (0..<max(0, days)).flatMap { offset -> [(date: Date, routineID: UUID)] in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return [] }
            return routineIDs(on: date, calendar: calendar).map { (date, $0) }
        }
    }

    /// Reschedules `date` to `routineID` (or to rest, when `nil`), writing an
    /// override so the date no longer follows the recurring weekday plan.
    public mutating func moved(date: Date, to routineID: UUID?, calendar: Calendar = .current) {
        moved(date: date, toRoutines: routineID.map { [$0] } ?? [], calendar: calendar)
    }

    /// Reschedules `date` to `routineIDs` in order (empty = rest), writing an
    /// override so the date no longer follows the recurring weekday plan.
    public mutating func moved(date: Date, toRoutines routineIDs: [UUID], calendar: Calendar = .current) {
        let key = DateKey.string(for: date, calendar: calendar)
        dateOverrides[key] = routineIDs
    }

    /// Appends `routineID` to `weekday`'s list unless it is already planned that day.
    public mutating func addRoutine(_ routineID: UUID, to weekday: Weekday) {
        var list = dayRoutines[weekday] ?? []
        guard !list.contains(routineID) else { return }
        list.append(routineID)
        dayRoutines[weekday] = list
    }

    /// Removes `routineID` from `weekday`; the day becomes rest when the list empties.
    public mutating func removeRoutine(_ routineID: UUID, from weekday: Weekday) {
        let list = (dayRoutines[weekday] ?? []).filter { $0 != routineID }
        dayRoutines[weekday] = list.isEmpty ? nil : list
    }

    /// Replaces `weekday`'s list wholesale (empty = rest).
    public mutating func setRoutines(_ routineIDs: [UUID], on weekday: Weekday) {
        dayRoutines[weekday] = routineIDs.isEmpty ? nil : routineIDs
    }
}
