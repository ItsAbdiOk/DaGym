import Foundation

/// What a long-pressed coach reply can be saved as, worked out from its text alone: the
/// library exercises it names (for "Save as note for Bench Press"), the text an exercise note
/// keeps, and the gist "Remember this" files as a memory fact. Pure, so a test can pin each;
/// the caller hands in plain text (`CoachMarkdown.plainText`) and the lifter's library.
public enum CoachChatSaveText {
    /// An exercise note is one card line, not the whole reply.
    public static let maxExerciseNoteLength = 300
    public static let exerciseNotePrefix = "Coach: "

    /// The library exercises `text` names, in order of first mention, each once, at most
    /// `limit`. A name counts only as whole words ("Row" is not inside "Rowing"), case-
    /// insensitively; a name inside a longer match ("Bench Press" inside "Incline Bench Press")
    /// does not count on its own. Equipment is not checked: a note is allowed on any exercise
    /// the lifter has, whether or not today's gym can do it.
    public static func exercisesNamed(
        in text: String, library: [SubstitutionCandidate], limit: Int = 4
    ) -> [SubstitutionCandidate] {
        var matches: [(range: Range<String.Index>, exercise: SubstitutionCandidate)] = []
        for exercise in library.sorted(by: { $0.name.count > $1.name.count }) {
            for range in wordRanges(of: exercise.name, in: text)
            where !matches.contains(where: { $0.range.overlaps(range) }) {
                matches.append((range, exercise))
            }
        }
        var seen: Set<UUID> = []
        let named = matches
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map(\.exercise)
            .filter { seen.insert($0.id).inserted }
        return Array(named.prefix(limit))
    }

    /// The note as it is stored on the exercise: "Coach: " and the reply, whitespace collapsed,
    /// cut to `maxExerciseNoteLength` with an ellipsis. nil when the reply is blank.
    public static func exerciseNote(_ text: String) -> String? {
        guard let collapsed = collapsed(text) else { return nil }
        let budget = maxExerciseNoteLength - exerciseNotePrefix.count
        guard collapsed.count > budget else { return exerciseNotePrefix + collapsed }
        return exerciseNotePrefix + collapsed.prefix(budget - 1) + "…"
    }

    /// The fact "Remember this" files: the reply's first sentence, plus following sentences
    /// while they fit `CoachMemoryValidation.maxTextLength`. A first sentence longer than that
    /// is cut, so a fact is never empty for a long reply. nil when the reply is blank.
    public static func memoryGist(_ text: String) -> String? {
        guard let collapsed = collapsed(text) else { return nil }
        var gist = ""
        for sentence in sentences(collapsed) {
            let candidate = gist.isEmpty ? sentence : gist + " " + sentence
            guard candidate.count <= CoachMemoryValidation.maxTextLength else { break }
            gist = candidate
        }
        return CoachMemoryValidation.normalizedText(gist.isEmpty ? collapsed : gist)
    }

    // MARK: - Helpers

    /// Whitespace runs collapsed to one space, trimmed; nil when nothing is left.
    private static func collapsed(_ text: String) -> String? {
        let joined = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// Split after ". ", "! " or "? " (and at the end); the terminator stays on its sentence.
    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if character == " ", let previous, ".!?".contains(previous) {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Every case-insensitive occurrence of `name` in `text` that stands as whole words.
    private static func wordRanges(of name: String, in text: String) -> [Range<String.Index>] {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        while searchStart < text.endIndex,
              let range = text.range(of: needle, options: options, range: searchStart..<text.endIndex) {
            searchStart = range.upperBound
            let start = range.lowerBound
            let before = start == text.startIndex ? nil : text[text.index(before: start)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if isWordCharacter(before) || isWordCharacter(after) { continue }
            ranges.append(range)
        }
        return ranges
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber
    }
}
