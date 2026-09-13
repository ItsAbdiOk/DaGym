import Foundation

/// §4.5 pattern 6: swap/switch/replace/change, add, and remove an exercise.
enum SwapAddRemovePattern {
    private static let swapTriggers: Set<String> = ["swap", "switch", "replace", "change"]
    private static let linkWords: Set<String> = ["for", "to", "with"]

    static func match(_ words: [String], context: ParseContext) -> ParseResult? {
        guard let first = words.first else { return nil }
        if swapTriggers.contains(first) { return swap(words, context: context) }
        if first == "add" { return addExercise(words, context: context) }
        if first == "remove" { return removeExercise(words, context: context) }
        return nil
    }

    private static func swap(_ words: [String], context: ParseContext) -> ParseResult? {
        let rest = Array(words.dropFirst())
        guard let linkIndex = rest.firstIndex(where: { linkWords.contains($0) }) else { return nil }
        let targetWords = Array(rest[..<linkIndex])
        let replacementWords = Array(rest[(linkIndex + 1)...])
        guard !replacementWords.isEmpty else { return nil }

        let target: ExerciseRef? = targetWords.isEmpty ? nil
            : (targetWords == ["this"] ? .onDeck
               : ExerciseMatcher.resolve(targetWords.joined(separator: " "), in: context))
        let replacement = ExerciseMatcher.resolve(
            replacementWords.joined(separator: " "), in: context
        )
        return ParseResult(
            commands: [.swapExercise(target: target, replacement: replacement)],
            confidence: 0.85, matchedPattern: "swap"
        )
    }

    private static func addExercise(_ words: [String], context: ParseContext) -> ParseResult? {
        let rest = Array(words.dropFirst())
        guard !rest.isEmpty, NumberWords.parse(rest, at: 0) == nil else { return nil }
        let phrase = rest.joined(separator: " ")
        let exercise = ExerciseMatcher.resolve(phrase, in: context)
        return ParseResult(
            commands: [.addExercise(exercise)], confidence: 0.85, matchedPattern: "addExercise"
        )
    }

    private static func removeExercise(_ words: [String], context: ParseContext) -> ParseResult? {
        let rest = Array(words.dropFirst())
        guard !rest.isEmpty else { return nil }
        let phrase = rest.joined(separator: " ")
        let exercise = ExerciseMatcher.resolve(phrase, in: context)
        return ParseResult(
            commands: [.removeExercise(exercise)], confidence: 0.85,
            matchedPattern: "removeExercise"
        )
    }
}
