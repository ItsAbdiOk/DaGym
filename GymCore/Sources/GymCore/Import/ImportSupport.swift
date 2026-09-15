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

/// Date formatters for the three exports' timestamp formats. Each is built once and shared:
/// `date(from:)` has been thread-safe since iOS 7 (`ISO8601DateFormatter` isn't marked
/// `Sendable`, hence the `nonisolated(unsafe)` on those two). Building a formatter per row used
/// to cost ~1–5 s on a 10k-row export, before any actual parsing.
///
/// Every row of a workout repeats the same timestamp text, so each entry point also memoises
/// the last string it parsed — the second and later rows of a session cost a string compare.
///
/// Each source tries its native format first, then a shared fallback list (recommendation 7) so a
/// file written by a slightly different app version or locale — an ISO `start_time`, a FitNotes
/// export with a time suffix — still parses instead of failing every row. Day-first numeric dates
/// ("07/03/2024") are deliberately never guessed at: a wrong guess would silently rewrite the
/// date, so that stays a per-row problem.
enum ImportDateFormat {
    /// Strong: "2024-03-11 18:24:00".
    static func strong(_ text: String) -> Date? {
        strongMemo.date(for: text) {
            strongFormatters[0].date(from: $0) ?? strongFormatters[1].date(from: $0) ?? fallback($0)
        }
    }

    /// Hevy: "11 Mar 2024, 18:24".
    static func hevy(_ text: String) -> Date? {
        hevyMemo.date(for: text) { hevyFormatter.date(from: $0) ?? fallback($0) }
    }

    /// FitNotes: "2024-03-11" (date only).
    static func fitNotes(_ text: String) -> Date? {
        fitNotesMemo.date(for: text) { fitNotesFormatter.date(from: $0) ?? fallback($0) }
    }

    private static let strongFormatters = [
        formatter(dateFormat: "yyyy-MM-dd HH:mm:ss"), formatter(dateFormat: "yyyy-MM-dd HH:mm")
    ]
    private static let hevyFormatter = formatter(dateFormat: "d MMM yyyy, HH:mm")
    private static let fitNotesFormatter = formatter(dateFormat: "yyyy-MM-dd")

    private static let fallbackFormats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm", "yyyy/MM/dd", "d MMM yyyy, HH:mm", "d MMM yyyy", "MMM d, yyyy"
    ]
    private static let fallbackFormatters = fallbackFormats.map(formatter(dateFormat:))
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()
    nonisolated(unsafe) private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso
    }()

    private static let strongMemo = LastParseMemo()
    private static let hevyMemo = LastParseMemo()
    private static let fitNotesMemo = LastParseMemo()

    private static func fallback(_ text: String) -> Date? {
        if let date = isoFormatter.date(from: text) ?? isoFractionalFormatter.date(from: text) { return date }
        for formatter in fallbackFormatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func formatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        return formatter
    }

    /// The last (text → result) pair one entry point produced, behind a lock so the importers
    /// stay callable from any thread. A miss (`nil`) is memoised too, so an unreadable date
    /// repeated down a whole workout isn't re-tried through nine fallbacks per row.
    private final class LastParseMemo: @unchecked Sendable {
        private let lock = NSLock()
        private var lastText: String?
        private var lastDate: Date?

        func date(for text: String, parse: (String) -> Date?) -> Date? {
            lock.lock()
            if lastText == text {
                let hit = lastDate
                lock.unlock()
                return hit
            }
            lock.unlock()
            let date = parse(text)
            lock.lock()
            lastText = text
            lastDate = date
            lock.unlock()
            return date
        }
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
    ///
    /// The unit has to be its own word — "Weight (kg)", "weight_lbs", "Weight kg" — not a
    /// substring: a header like "Weight (kg/lb)" or "weight_lbs_or_kg" names both, and the old
    /// `contains("lb")` picked lb for either. Two units in one header resolve to `nil` and let
    /// the per-row column or the user decide.
    static func columnUnit(named weightColumn: String) -> WeightUnit? {
        let words = weightColumn.lowercased().components(separatedBy: CharacterSet.letters.inverted)
        let namesLb = words.contains { $0 == "lb" || $0 == "lbs" }
        let namesKg = words.contains { $0 == "kg" || $0 == "kgs" }
        switch (namesLb, namesKg) {
        case (true, false): return .lb
        case (false, true): return .kg
        default: return nil
        }
    }
}
