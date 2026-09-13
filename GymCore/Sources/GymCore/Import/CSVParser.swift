import Foundation

/// A minimal RFC-4180-ish CSV parser: quoted fields, `""` as an escaped quote inside a quoted
/// field, commas and newlines allowed inside quotes, and `\r\n`/`\n`/`\r` line endings. Good
/// enough for the exports `Import/WorkoutImport.swift` reads (Strong, Hevy, FitNotes) — none of
/// which use multi-byte delimiters or exotic quoting.
///
/// Scans Unicode scalars rather than `Character`s: Swift's grapheme-cluster rules merge a bare
/// `\r\n` into a single `Character`, which would make a plain `case "\r", "\n":` switch miss a
/// CRLF line ending entirely.
public enum CSVParser {
    /// Parses `text` into rows of fields. A trailing blank line produces no extra empty row. A
    /// leading UTF-8 BOM (some exports, notably Excel-authored CSVs, write one) is stripped first
    /// so it never ends up glued to the first header cell.
    public static func parse(_ text: String) -> [[String]] {
        var text = text
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        var state = ParserState()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if state.inQuotes {
                index = state.consumeQuoted(scalar, scalars: scalars, index: index)
                continue
            }
            index = state.consumeUnquoted(scalar, scalars: scalars, index: index)
        }
        state.flushTrailingField()
        return state.rows
    }

    /// Mutable scan state, kept as one value so the per-scalar helpers stay under the
    /// parameter-count limit instead of threading five separate `inout` arguments.
    private struct ParserState {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var sawAnyField = false

        /// Handles one scalar while inside a quoted field, including the `""` escape and the
        /// closing quote. Returns the next index to resume from.
        mutating func consumeQuoted(_ scalar: Unicode.Scalar, scalars: [Unicode.Scalar], index: Int) -> Int {
            guard scalar == "\"" else {
                field.unicodeScalars.append(scalar)
                return index + 1
            }
            if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                field.append("\"")
                return index + 2
            }
            inQuotes = false
            return index + 1
        }

        /// Handles one scalar outside a quoted field: quote-open, field/row separators, or a
        /// plain scalar. Returns the next index to resume from.
        mutating func consumeUnquoted(
            _ scalar: Unicode.Scalar, scalars: [Unicode.Scalar], index: Int
        ) -> Int {
            switch scalar {
            case "\"":
                inQuotes = true
                sawAnyField = true
            case ",":
                row.append(field)
                field = ""
                sawAnyField = true
            case "\r", "\n":
                return endLine(scalar, scalars: scalars, index: index)
            default:
                field.unicodeScalars.append(scalar)
                sawAnyField = true
            }
            return index + 1
        }

        /// Ends the current row on `\r`, `\n` or `\r\n`. Returns the next index to resume from.
        private mutating func endLine(
            _ scalar: Unicode.Scalar, scalars: [Unicode.Scalar], index: Int
        ) -> Int {
            row.append(field)
            field = ""
            rows.append(row)
            row = []
            sawAnyField = false
            var nextIndex = index + 1
            if scalar == "\r", nextIndex < scalars.count, scalars[nextIndex] == "\n" {
                nextIndex += 1
            }
            return nextIndex
        }

        mutating func flushTrailingField() {
            guard sawAnyField || !field.isEmpty || !row.isEmpty else { return }
            row.append(field)
            rows.append(row)
        }
    }
}
