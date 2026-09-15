import Foundation

/// The bounds every imported number has to fall inside. A third-party export is untrusted input:
/// a hand-edited or corrupt cell can carry `inf`, `nan`, `1e999`, `9223372036854775807` or a
/// negative weight, and the app has to reject the row rather than trap on the conversion or store
/// a value that later breaks something else (a non-finite weight makes `JSONEncoder` throw, so a
/// single bad row would make every future backup fail).
///
/// The ceilings are deliberately far above anything real — no lifter benches 600 kg or does
/// 1,000 reps — so a legitimate row is never rejected, while a nonsense one never lands.
enum ImportLimits {
    /// `TrainingConstants.maxLoadKg` — the same ceiling voice logging and plan sanitising use.
    static let maxWeightKg = TrainingConstants.maxLoadKg
    static let maxReps = 1000
    /// One week, in seconds: longer than any set, hold or cardio bout.
    static let maxDurationSeconds = 60 * 60 * 24 * 7
    /// 1,000 km.
    static let maxDistanceMeters = 1_000_000.0
    /// Notes/instructions from an untrusted file are truncated to this, so one pathological cell
    /// can't put a megabyte of text on an exercise.
    static let maxTextLength = 2000
}

/// Numeric and duration parsing shared by the three importers. Every entry point here is total:
/// it returns `nil` for anything it cannot represent safely, and never traps.
enum ImportParsing {
    /// Locale-independent number parsing. The exports normally use `.` as the decimal separator;
    /// a European export (FitNotes/spreadsheets) sometimes writes a bare comma instead ("82,5") —
    /// accepted only when there's exactly one comma and no dot, since a thousands-grouped value
    /// like "1,000.5" mixing both is ambiguous and left as a problem row instead of guessed at.
    ///
    /// Non-finite results are rejected outright: `Double("1e999")` is `+inf` and `Double("nan")`
    /// is a NaN, and both would otherwise trap the moment anything converted them to `Int`.
    static func double(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed) { return value.isFinite ? value : nil }
        guard trimmed.filter({ $0 == "," }).count == 1, !trimmed.contains(".") else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return value.isFinite ? value : nil
    }

    /// An integer cell. Falls back to rounding a decimal one ("8.0"), but only from a magnitude
    /// `Int` can actually hold — `Int(Double.infinity)` and `Int(Double.nan)` both trap.
    static func int(_ text: String?) -> Int? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = Int(trimmed) { return value }
        guard let value = double(trimmed) else { return nil }
        let rounded = value.rounded()
        guard rounded >= -9e15, rounded <= 9e15 else { return nil }
        return Int(rounded)
    }

    /// A reps cell → a count inside `0...ImportLimits.maxReps`, or `nil` when it's unreadable or
    /// out of range (negative reps, 10^9 reps) so the caller can report the row as a problem
    /// instead of storing a value that would crown a bogus personal record.
    static func reps(_ text: String) -> Int? {
        guard let value = int(text), (0...ImportLimits.maxReps).contains(value) else { return nil }
        return value
    }

    /// Effort hygiene for an imported RPE column (recommendation 3): blank/non-numeric/≤0 is
    /// unrated rather than a bogus low effort; anything above the 1–10 scale (Hevy sometimes
    /// exports 0–100 "difficulty") clamps to the max instead of being stored verbatim. Anything
    /// below `Effort.minimumRPE` is unrated too: `Effort(rpe:)` clamps up to 5, so an RPE 4 set
    /// would otherwise be stored as "RPE 5, five in the tank" rather than "not rated".
    static func rpe(_ text: String?) -> Double? {
        guard let value = double(text), value > 0 else { return nil }
        guard value >= Effort.minimumRPE else { return nil }
        return min(value, 10)
    }

    /// The unit named by a per-row unit column ("Weight Unit"/"unit"), or `nil` when the text
    /// names neither kg nor lb (missing column, unrecognised value).
    static func weightUnit(from text: String?) -> WeightUnit? {
        guard let text else { return nil }
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "kg", "kgs", "kilogram", "kilograms": return .kg
        case "lb", "lbs", "pound", "pounds": return .lb
        default: return nil
        }
    }

    /// A weight column's raw text, converted to kg. `columnUnit` is the unit the column header
    /// itself named (e.g. "Weight (lbs)"); when the header is ambiguous (bare "Weight") a sibling
    /// per-row unit column decides, then the unit the user picked in the preview (`assumedUnit`),
    /// and a file with none of the three is read as kg.
    ///
    /// Returns `nil` for anything non-finite, negative, or beyond `ImportLimits.maxWeightKg`, so
    /// the row becomes a reported problem rather than an un-encodable set log.
    static func weightKg(
        _ text: String, columnUnit: WeightUnit?, perRowUnit: String?, assumedUnit: WeightUnit? = nil
    ) -> Double? {
        guard let value = double(text) else { return nil }
        let unit = columnUnit ?? weightUnit(from: perRowUnit) ?? assumedUnit ?? .kg
        let kg = unit.toKg(value)
        guard kg.isFinite, kg >= 0, kg <= ImportLimits.maxWeightKg else { return nil }
        return kg
    }

    /// "1h 5m", "65m", "45s" (Strong's free-text workout duration) → seconds. Returns `nil` on
    /// anything that would overflow rather than trapping on the multiply.
    static func durationSecondsFromFreeText(_ text: String?) -> Int? {
        guard let text else { return nil }
        var total = 0
        var matched = false
        for token in tokens(in: text) {
            guard !token.digits.isEmpty else { continue }
            guard let value = Int(token.digits) else { return nil }
            let multiplier: Int
            switch token.unit {
            case "h": multiplier = 3600
            case "m": multiplier = 60
            case "s": multiplier = 1
            default: continue
            }
            guard let sum = add(total, value, times: multiplier) else { return nil }
            total = sum
            matched = true
        }
        return matched ? duration(total) : nil
    }

    private static func tokens(in text: String) -> [(digits: String, unit: String)] {
        var results: [(digits: String, unit: String)] = []
        var digits = ""
        for character in text.lowercased() {
            if character.isNumber {
                digits.append(character)
            } else if character.isLetter, !digits.isEmpty {
                results.append((digits, String(character)))
                digits = ""
            } else if !character.isNumber {
                digits = ""
            }
        }
        return results
    }

    /// "45", "0:45", "1:02:03" (FitNotes/Hevy-style clock durations) → seconds, or `nil` when a
    /// component is unreadable or the total overflows/exceeds `ImportLimits.maxDurationSeconds`.
    static func durationSecondsFromClock(_ text: String?) -> Int? {
        guard let text else { return nil }
        let rawParts = text.split(separator: ":")
        guard rawParts.count > 1 else { return duration(int(text)) }
        let parts = rawParts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == rawParts.count else { return nil }
        let multipliers: [Int]
        switch parts.count {
        case 2: multipliers = [60, 1]
        case 3: multipliers = [3600, 60, 1]
        default: return nil
        }
        var total = 0
        for (value, multiplier) in zip(parts, multipliers) {
            guard let sum = add(total, value, times: multiplier) else { return nil }
            total = sum
        }
        return duration(total)
    }

    /// `total + value * multiplier`, or `nil` if either step overflows `Int`.
    private static func add(_ total: Int, _ value: Int, times multiplier: Int) -> Int? {
        let (product, productOverflowed) = value.multipliedReportingOverflow(by: multiplier)
        guard !productOverflowed else { return nil }
        let (sum, sumOverflowed) = total.addingReportingOverflow(product)
        return sumOverflowed ? nil : sum
    }

    /// A duration in seconds, or `nil` when it's negative or longer than a week.
    static func duration(_ value: Int?) -> Int? {
        guard let value, (0...ImportLimits.maxDurationSeconds).contains(value) else { return nil }
        return value
    }

    /// A distance in the named unit → meters, or `nil` when it's non-finite, negative or beyond
    /// `ImportLimits.maxDistanceMeters`.
    static func metersFromDistance(_ value: Double?, unit: String) -> Double? {
        guard let value else { return nil }
        let meters: Double
        switch unit.lowercased() {
        case "mi", "mile", "miles": meters = value * 1609.344
        case "m", "meter", "meters", "metres": meters = value
        case "yd", "yard", "yards": meters = value * 0.9144
        case "ft", "feet": meters = value * 0.3048
        default: meters = value * 1000
        }
        guard meters.isFinite, meters >= 0, meters <= ImportLimits.maxDistanceMeters else { return nil }
        return meters
    }

    /// The distance unit a column *name* implies ("distance_miles", "Distance (km)"), for exports
    /// that carry the unit in the header instead of a sibling unit column.
    static func distanceUnit(fromColumnName name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("mile") || lower.contains("_mi") || lower.contains("(mi") { return "mi" }
        if lower.contains("km") || lower.contains("kilomet") { return "km" }
        if lower.contains("meter") || lower.contains("metre") { return "m" }
        return nil
    }

    /// Free text from an untrusted file, trimmed and capped at `ImportLimits.maxTextLength`.
    static func text(_ value: String?) -> String {
        guard let value else { return "" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > ImportLimits.maxTextLength else { return trimmed }
        return String(trimmed.prefix(ImportLimits.maxTextLength))
    }
}
