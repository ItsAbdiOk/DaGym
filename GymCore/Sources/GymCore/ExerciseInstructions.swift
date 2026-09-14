import Foundation

/// One rendered chunk of an exercise's "How To Do It" text.
///
/// `number` is `nil` for text that was never numbered in the first place — most wger-sourced
/// instructions are prose, and they must render exactly as they always have rather than being
/// forced into a list.
public struct ExerciseInstructionStep: Equatable, Sendable, Identifiable {
    /// 1-based step number, or `nil` for an unnumbered block.
    public let number: Int?
    public let text: String

    public var id: Int { number ?? 0 }

    public init(number: Int?, text: String) {
        self.number = number
        self.text = text
    }
}

/// Splits a seeded exercise's instructions into steps.
///
/// The seed stores instructions as one string with the numbering inline:
/// `"1. Lie on your back… 2. Engage your core… 3. Pause briefly, then lower back down with
/// control. Keep your neck neutral."` — so the steps have to be recovered from the `N.` markers
/// rather than from sentence boundaries. Several steps carry a trailing coaching sentence after
/// the numbered clause (step 3 above), and that sentence belongs to its step, not to a step 4.
///
/// A block of text only becomes a list when it really looks like one:
///
/// - the very first thing in the string is the marker `1.`,
/// - the markers run consecutively (`1.`, `2.`, `3.`, …) — a stray number out of sequence is
///   left inside the step text, so "hold for 3. " mid-sentence cannot start a new step,
/// - each marker sits at the start of the string or after whitespace, and is followed by
///   whitespace — so "2.5 kg" and "v1.2" are never markers,
/// - and there are at least two of them.
///
/// Anything else comes back as a single unnumbered step holding the original text.
public enum ExerciseInstructions {
    public static func steps(from raw: String) -> [ExerciseInstructionStep] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let markers = consecutiveMarkers(in: trimmed)
        guard markers.count >= 2, markers[0].range.lowerBound == trimmed.startIndex else {
            return [ExerciseInstructionStep(number: nil, text: trimmed)]
        }

        var steps: [ExerciseInstructionStep] = []
        for (offset, marker) in markers.enumerated() {
            let end = offset + 1 < markers.count ? markers[offset + 1].range.lowerBound : trimmed.endIndex
            let body = trimmed[marker.range.upperBound..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            steps.append(ExerciseInstructionStep(number: marker.number, text: body))
        }
        // A list whose markers all turned out to have empty bodies is not a list.
        return steps.count >= 2 ? steps : [ExerciseInstructionStep(number: nil, text: trimmed)]
    }

    private struct Marker {
        let number: Int
        /// Covers the digits and the dot, so `range.upperBound` is where the step text begins.
        let range: Range<String.Index>
    }

    /// Every `N.` marker that continues the run 1, 2, 3, … Out-of-sequence numbers are skipped
    /// rather than ending the scan, so one odd "3." inside a sentence does not truncate the list.
    private static func consecutiveMarkers(in text: String) -> [Marker] {
        var markers: [Marker] = []
        var expected = 1
        var index = text.startIndex

        while index < text.endIndex {
            guard
                isMarkerStart(text, at: index),
                let marker = marker(in: text, at: index),
                marker.number == expected
            else {
                index = text.index(after: index)
                continue
            }
            markers.append(marker)
            expected += 1
            index = marker.range.upperBound
        }
        return markers
    }

    /// A marker may only begin the string or follow whitespace — never mid-token, so a decimal's
    /// second half or a version number can never be mistaken for one.
    private static func isMarkerStart(_ text: String, at index: String.Index) -> Bool {
        guard text[index].isNumber else { return false }
        guard index > text.startIndex else { return true }
        return text[text.index(before: index)].isWhitespace
    }

    /// Reads `digits + "."` at `index`, requiring whitespace (or the end of the string) after the
    /// dot so that "2.5 kg" is not a marker.
    private static func marker(in text: String, at index: String.Index) -> Marker? {
        var cursor = index
        var digits = ""
        while cursor < text.endIndex, text[cursor].isNumber {
            digits.append(text[cursor])
            cursor = text.index(after: cursor)
        }
        guard digits.count <= 2, let number = Int(digits) else { return nil }
        guard cursor < text.endIndex, text[cursor] == "." else { return nil }
        let afterDot = text.index(after: cursor)
        guard afterDot == text.endIndex || text[afterDot].isWhitespace else { return nil }
        return Marker(number: number, range: index..<afterDot)
    }
}
