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

/// Validating readers for the measured columns of one CSV row, shared by the three importers.
/// Each throws `ImportRowError` when a cell is *present but unusable* — unreadable, non-finite,
/// negative or beyond `ImportLimits` — so the row is reported as a problem instead of silently
/// dropping the value or storing something that breaks later. An absent (or blank) cell is `nil`.
///
/// A measured-zero (`0` distance, `0` seconds) reads as "not measured", because real exports —
/// Strong in particular — write `0` rather than an empty cell in the `Distance`/`Seconds` columns
/// of every ordinary weight set.
enum ImportRow {
    static func reps(_ text: String?) throws -> Int {
        guard let text else { return 0 }
        guard let value = ImportParsing.reps(text) else {
            throw ImportRowError("Unreadable or out-of-range reps value \"\(text)\".")
        }
        return value
    }

    /// A clock-or-plain duration cell ("45", "1:02:03").
    static func clockDuration(_ text: String?) throws -> Int? {
        guard let text else { return nil }
        guard let value = ImportParsing.durationSecondsFromClock(text) else {
            throw ImportRowError("Unreadable or out-of-range duration value \"\(text)\".")
        }
        return value == 0 ? nil : value
    }

    /// A plain seconds cell (Strong's `Seconds`, Hevy's `duration_seconds`).
    static func seconds(_ text: String?) throws -> Int? {
        guard let text else { return nil }
        guard let value = ImportParsing.duration(ImportParsing.int(text)) else {
            throw ImportRowError("Unreadable or out-of-range duration value \"\(text)\".")
        }
        return value == 0 ? nil : value
    }

    static func distance(_ text: String?, unit: String) throws -> Double? {
        guard let text else { return nil }
        guard let raw = ImportParsing.double(text),
              let meters = ImportParsing.metersFromDistance(raw, unit: unit) else {
            throw ImportRowError("Unreadable or out-of-range distance value \"\(text)\".")
        }
        return meters == 0 ? nil : meters
    }

    static func weightKg(
        _ text: String?, columnUnit: WeightUnit?, perRowUnit: String?, assumedUnit: WeightUnit?
    ) throws -> Double {
        guard let text else { return 0 }
        guard let value = ImportParsing.weightKg(
            text, columnUnit: columnUnit, perRowUnit: perRowUnit, assumedUnit: assumedUnit
        ) else {
            throw ImportRowError("Unreadable or out-of-range weight value \"\(text)\".")
        }
        return value
    }

    /// The `WeightUnit` a column header names ("Weight (lbs)", "weight_kg"), or `nil` when the
    /// header is bare and a per-row unit column (or the user) has to decide.
    static func columnUnit(named weightColumn: String) -> WeightUnit? {
        if weightColumn.contains("lb") { return .lb }
        if weightColumn.contains("kg") { return .kg }
        return nil
    }
}
