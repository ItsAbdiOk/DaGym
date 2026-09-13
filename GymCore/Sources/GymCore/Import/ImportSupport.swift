import Foundation

/// Header-name → column-index lookup shared by the three CSV importers. Column names are
/// matched case-insensitively and trimmed, since exports vary in casing.
struct ColumnMap {
    private let index: [String: Int]

    init(header: [String]) {
        var map: [String: Int] = [:]
        for (position, column) in header.enumerated() {
            map[Self.key(column)] = position
        }
        index = map
    }

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The trimmed value of `name` in `row`, or `nil` if the column is missing or blank.
    func value(_ row: [String], _ name: String) -> String? {
        guard let position = index[Self.key(name)], position < row.count else { return nil }
        let trimmed = row[position].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The header column whose name contains every word in `containing` (case-insensitive) — used
    /// to find a weight/distance column whose exact name carries a unit, e.g. "Weight (kg)".
    /// Deterministic: an exact match to the joined words wins outright (so "Weight" beats "Weight
    /// Unit" when both are present); otherwise the alphabetically first candidate is picked,
    /// rather than `Dictionary.keys.first`, whose order isn't stable across launches.
    func columnName(containing words: [String]) -> String? {
        let candidates = index.keys.filter { key in words.allSatisfy { key.contains($0) } }.sorted()
        let exact = words.joined(separator: " ")
        if candidates.contains(exact) { return exact }
        return candidates.first
    }

    var isEmpty: Bool { index.isEmpty }
}

/// Numeric and duration parsing shared by the three importers.
enum ImportParsing {
    /// Locale-independent number parsing. The exports normally use `.` as the decimal separator;
    /// a European export (FitNotes/spreadsheets) sometimes writes a bare comma instead ("82,5") —
    /// accepted only when there's exactly one comma and no dot, since a thousands-grouped value
    /// like "1,000.5" mixing both is ambiguous and left as a problem row instead of guessed at.
    static func double(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed) { return value }
        guard trimmed.filter({ $0 == "," }).count == 1, !trimmed.contains(".") else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    static func int(_ text: String?) -> Int? {
        guard let text else { return nil }
        if let value = Int(text) { return value }
        return double(text).map { Int($0.rounded()) }
    }

    /// Effort hygiene for an imported RPE column (recommendation 3): blank/non-numeric/≤0 is
    /// unrated rather than a bogus low effort; anything above the 1–10 scale (Hevy sometimes
    /// exports 0–100 "difficulty") clamps to the max instead of being stored verbatim.
    static func rpe(_ text: String?) -> Double? {
        guard let value = double(text), value > 0 else { return nil }
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
    /// per-row unit column decides instead, and a file with neither is assumed to already be kg.
    static func weightKg(_ text: String, columnUnit: WeightUnit?, perRowUnit: String?) -> Double? {
        guard let value = double(text) else { return nil }
        if let columnUnit { return columnUnit.toKg(value) }
        if let rowUnit = weightUnit(from: perRowUnit) { return rowUnit.toKg(value) }
        return value
    }

    /// "1h 5m", "65m", "45s" (Strong's free-text workout duration) → seconds.
    static func durationSecondsFromFreeText(_ text: String?) -> Int? {
        guard let text else { return nil }
        var total = 0
        var matched = false
        for token in tokens(in: text) {
            guard let value = Int(token.digits), !token.digits.isEmpty else { continue }
            matched = true
            switch token.unit {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: break
            }
        }
        return matched ? total : nil
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

    /// "45", "0:45", "1:02:03" (FitNotes/Hevy-style clock durations) → seconds.
    static func durationSecondsFromClock(_ text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return int(text) }
        switch parts.count {
        case 1: return parts[0]
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    static func metersFromDistance(_ value: Double?, unit: String) -> Double? {
        guard let value else { return nil }
        switch unit.lowercased() {
        case "mi", "mile", "miles": return value * 1609.344
        case "km", "kilometers", "kilometres": return value * 1000
        case "m", "meter", "meters", "metres": return value
        default: return value * 1000
        }
    }
}

/// Date formatters for the three exports' timestamp formats. `DateFormatter` is not `Sendable`,
/// so each is built fresh per call — these files parse at most a few thousand rows, so the cost
/// is negligible.
///
/// Each source tries its native format first, then a shared fallback list (recommendation 7) so a
/// file written by a slightly different app version or locale — an ISO `start_time`, a FitNotes
/// export with a time suffix — still parses instead of failing every row. Day-first numeric dates
/// ("07/03/2024") are deliberately never guessed at: a wrong guess would silently rewrite the
/// date, so that stays a per-row problem.
enum ImportDateFormat {
    /// Strong: "2024-03-11 18:24:00".
    static func strong(_ text: String) -> Date? {
        formatter(dateFormat: "yyyy-MM-dd HH:mm:ss").date(from: text)
            ?? formatter(dateFormat: "yyyy-MM-dd HH:mm").date(from: text)
            ?? fallback(text)
    }

    /// Hevy: "11 Mar 2024, 18:24".
    static func hevy(_ text: String) -> Date? {
        formatter(dateFormat: "d MMM yyyy, HH:mm").date(from: text) ?? fallback(text)
    }

    /// FitNotes: "2024-03-11" (date only).
    static func fitNotes(_ text: String) -> Date? {
        formatter(dateFormat: "yyyy-MM-dd").date(from: text) ?? fallback(text)
    }

    private static let fallbackFormats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm", "yyyy/MM/dd", "d MMM yyyy, HH:mm", "d MMM yyyy", "MMM d, yyyy"
    ]

    private static func fallback(_ text: String) -> Date? {
        if let date = isoDate(text) { return date }
        for format in fallbackFormats {
            if let date = formatter(dateFormat: format).date(from: text) { return date }
        }
        return nil
    }

    private static func isoDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text)
    }

    private static func formatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        return formatter
    }
}
