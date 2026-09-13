import Foundation

/// §4.5 patterns 7–8: freeform notes and read-only training queries.
enum NoteQueryPattern {
    static func matchNote(_ words: [String], rawText: String) -> ParseResult? {
        guard words.first == "note" else { return nil }
        let text = words.dropFirst().joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return ParseResult(
            commands: [.addNote(exercise: .onDeck, text: text)], confidence: 0.9, matchedPattern: "note"
        )
    }

    static func matchQuery(_ words: [String], context: ParseContext) -> ParseResult? {
        if words.contains("my-pr") || words.contains("best") {
            let exercise = queryExercise(words, context: context)
            return ParseResult(
                commands: [.query(.personalRecord(exercise))], confidence: 0.9,
                matchedPattern: "queryPR"
            )
        }
        guard words.contains("last-time") || (words.contains("what") && words.contains("did"))
        else { return nil }
        let exercise = queryExercise(words, context: context)
        return ParseResult(
            commands: [.query(.lastSession(exercise))], confidence: 0.9,
            matchedPattern: "queryLastSession"
        )
    }

    private static func queryExercise(_ words: [String], context: ParseContext) -> ExerciseRef {
        let stop = ExercisePhrase.stopWords.union(["do", "lift", "bench"])
        let leftover = words.filter { !stop.contains($0) }
        guard !leftover.isEmpty else { return .onDeck }
        return ExerciseMatcher.resolve(leftover.joined(separator: " "), in: context)
    }
}
