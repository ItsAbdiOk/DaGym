import Foundation

/// The unit a user sees distances in. Storage is always metres (the same rule kg has for
/// weight, plan.md §3); this type is the single place conversions and formatting happen.
public enum DistanceUnit: String, CaseIterable, Codable, Sendable {
    case km
    case mi

    public static let metersPerMile = 1609.344

    public var symbol: String {
        switch self {
        case .km: return "km"
        case .mi: return "mi"
        }
    }

    /// Metres in one of this unit.
    public var meters: Double {
        switch self {
        case .km: return 1000
        case .mi: return Self.metersPerMile
        }
    }

    /// Converts canonical metres to this unit, unrounded.
    public func display(meters: Double) -> Double { meters / self.meters }

    /// Converts a value already in this unit back to metres.
    public func toMeters(_ value: Double) -> Double { value * meters }

    /// A canonical distance in this unit with two decimals: "5.00", "3.11". The trailing zeros
    /// stay so a column of distances lines up the way a column of times does.
    public func format(meters: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", display(meters: meters))
    }

    /// "5.00 km", "3.11 mi".
    public func formatWithSymbol(meters: Double, decimals: Int = 2) -> String {
        "\(format(meters: meters, decimals: decimals)) \(symbol)"
    }

    /// The unit a lifter who thinks in `weightUnit` most likely runs in: lb users get miles.
    public static func matching(_ weightUnit: WeightUnit) -> DistanceUnit {
        weightUnit == .lb ? .mi : .km
    }
}

/// Pace and speed maths for a cardio set. Everything takes canonical metres and seconds and
/// answers nil (never 0 or infinity) when either is missing, so a row with a distance typed in
/// but no time yet shows "–" rather than "0:00 /km".
public enum CardioPace {
    /// The shortest distance a pace is computed over. A sub-metre distance — a "0.000001 km"
    /// cell an import let through — produced a finite but absurd pace ("277777:46 /km") that
    /// then reached the pace string and the fastest-pace PR comparison.
    public static let minimumDistanceMeters = 1.0

    /// The most whole seconds a pace or hold is ever rendered as (a week). Keeps `Int(_:)`
    /// off values that could trap, whatever upstream let through.
    static let maxClockSeconds = 7 * 24 * 3600

    /// Seconds per one `unit` of distance, or nil when there is no time or the distance is
    /// under `minimumDistanceMeters`.
    public static func secondsPerUnit(
        distanceMeters: Double, durationSeconds: Int, unit: DistanceUnit
    ) -> Double? {
        guard distanceMeters >= minimumDistanceMeters, durationSeconds > 0 else { return nil }
        return Double(durationSeconds) / unit.display(meters: distanceMeters)
    }

    /// Distance units per hour, or nil when there is no time or the distance is under
    /// `minimumDistanceMeters`.
    public static func unitsPerHour(
        distanceMeters: Double, durationSeconds: Int, unit: DistanceUnit
    ) -> Double? {
        guard distanceMeters >= minimumDistanceMeters, durationSeconds > 0 else { return nil }
        return unit.display(meters: distanceMeters) / (Double(durationSeconds) / 3600)
    }

    /// "5:06 /km" — the pace rounded to the nearest whole second. Nil when there is no pace.
    public static func formatPace(
        distanceMeters: Double, durationSeconds: Int, unit: DistanceUnit
    ) -> String? {
        secondsPerUnit(distanceMeters: distanceMeters, durationSeconds: durationSeconds, unit: unit)
            .map { "\(clock(wholeSeconds($0))) /\(unit.symbol)" }
    }

    /// `seconds` rounded to a whole number and clamped to `0…maxClockSeconds`; a NaN reads as 0
    /// and an infinity clamps like any other out-of-range value.
    public static func wholeSeconds(_ seconds: Double) -> Int {
        guard !seconds.isNaN else { return 0 }
        return Int(min(max(seconds.rounded(), 0), Double(maxClockSeconds)))
    }

    /// "11.8 km/h". Nil when there is no speed.
    public static func formatSpeed(
        distanceMeters: Double, durationSeconds: Int, unit: DistanceUnit
    ) -> String? {
        unitsPerHour(distanceMeters: distanceMeters, durationSeconds: durationSeconds, unit: unit)
            .map { String(format: "%.1f %@/h", $0, unit.symbol) }
    }

    /// "25:30", or "1:02:05" once an hour is crossed — a run is not a plank.
    public static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
