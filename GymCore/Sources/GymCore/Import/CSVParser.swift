import Foundation

// `String(decoding:as: UTF8.self)` is deliberate throughout this file, and the linter's preferred
// `String(bytes:encoding:)` would be wrong here: it returns nil on malformed UTF-8, which would
// turn one bad byte in a user's export into a lost field. The lossy initializer substitutes a
// replacement character and keeps the row.
// swiftlint:disable optional_data_string_conversion

/// A minimal RFC-4180-ish CSV parser: quoted fields, `""` as an escaped quote inside a quoted
/// field, commas and newlines allowed inside quotes, and `\r\n`/`\n`/`\r` line endings. Good
/// enough for the exports `Import/WorkoutImport.swift` reads (Strong, Hevy, FitNotes) — none of
/// which use multi-byte delimiters or exotic quoting.
///
/// Scans **UTF-8 bytes**, not `Character`s: Swift's grapheme-cluster rules merge a bare `\r\n`
/// into a single `Character`, which would make a plain `case "\r", "\n":` switch miss a CRLF line
/// ending entirely. Bytes also make the common case cheap — an unquoted field is one contiguous
/// range, decoded into a `String` once, rather than a `String` grown one scalar at a time. That
/// difference is the whole cost of the parse on a real file: a 50 MB export went from minutes to
/// a couple of seconds, which is a user staring at a spinner versus not.
///
/// Every delimiter (`,`, `"`, `\r`, `\n`) is a single ASCII byte that can never appear inside a
/// multi-byte UTF-8 sequence, so scanning bytes can't split a character; any invalid UTF-8 in the
/// file is repaired with replacement characters by `String(decoding:)` rather than failing.
public enum CSVParser {
    private static let comma = UInt8(ascii: ",")
    private static let quote = UInt8(ascii: "\"")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let newline = UInt8(ascii: "\n")

    /// The most a file may weigh before `parse` refuses it. `parse` copies the whole text into a
    /// byte array; a 200 MB paste would be copied whole and could take the app down. A real
    /// export is a few MB — years of Strong history is under 10 — so 64 MB is far above anything
    /// legitimate. `WorkoutImport.parse` reports an oversized file as an `ImportProblem`.
    public static let maxBytes = 64 * 1024 * 1024

    /// Whether `text` is over `maxBytes`. O(1) for a native string.
    public static func isOversized(_ text: String) -> Bool {
        text.utf8.count > maxBytes
    }

    /// Parses `text` into rows of fields. A trailing blank line produces no extra empty row. A
    /// leading UTF-8 BOM (some exports, notably Excel-authored CSVs, write one) is stripped first
    /// so it never ends up glued to the first header cell. Anything over `maxBytes` parses as
    /// no rows at all — check `isOversized` first to tell that apart from an empty file.
    public static func parse(_ text: String) -> [[String]] {
        guard !isOversized(text) else { return [] }
        var bytes = Array(text.utf8)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
        }
        var state = ParserState(bytes: bytes)
        state.run()
        return state.rows
    }

    /// Mutable scan state, kept as one value so the per-field helpers stay under the
    /// parameter-count limit instead of threading five separate `inout` arguments.
    private struct ParserState {
        let bytes: [UInt8]
        var index = 0
        var rows: [[String]] = []
        var row: [String] = []
        /// True once the current row has produced at least one field position, so a file ending
        /// in a newline doesn't yield a trailing empty row while `a,,` still yields three fields.
        var sawAnyField = false

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func run() {
            while index < bytes.count {
                row.append(readField())
                sawAnyField = true
                guard index < bytes.count else { break }
                let byte = bytes[index]
                index += 1
                if byte == comma { continue }
                // A `\r`, a `\n`, or a `\r\n` pair ends the row.
                if byte == carriageReturn, index < bytes.count, bytes[index] == newline {
                    index += 1
                }
                endRow()
            }
            if sawAnyField { endRow() }
        }

        private mutating func endRow() {
            rows.append(row)
            row = []
            sawAnyField = false
        }

        /// Reads one field, leaving `index` on its terminator (comma, line ending) or at the end
        /// of the input. An unquoted field is a single contiguous byte range and is decoded in one
        /// go; only a quoted field with an escaped `""` needs a byte buffer.
        private mutating func readField() -> String {
            guard index < bytes.count, bytes[index] == quote else { return readUnquoted() }
            index += 1
            return readQuoted()
        }

        private mutating func readUnquoted() -> String {
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                if byte == comma || byte == newline || byte == carriageReturn { break }
                index += 1
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        private mutating func readQuoted() -> String {
            var start = index
            var buffer: [UInt8] = []
            while index < bytes.count {
                guard bytes[index] == quote else {
                    index += 1
                    continue
                }
                // `""` inside a quoted field is one literal quote.
                if index + 1 < bytes.count, bytes[index + 1] == quote {
                    buffer.append(contentsOf: bytes[start..<index])
                    buffer.append(quote)
                    index += 2
                    start = index
                    continue
                }
                let field = finish(buffer: &buffer, from: start, to: index)
                index += 1
                return field
            }
            // An unterminated quote: take everything to the end rather than losing the row.
            return finish(buffer: &buffer, from: start, to: bytes.count)
        }

        private func finish(buffer: inout [UInt8], from start: Int, to end: Int) -> String {
            guard !buffer.isEmpty else { return String(decoding: bytes[start..<end], as: UTF8.self) }
            buffer.append(contentsOf: bytes[start..<end])
            return String(decoding: buffer, as: UTF8.self)
        }
    }
}

// swiftlint:enable optional_data_string_conversion
