import Foundation

/// "bench eight at a hundred and rows eight at seventy" — two independent
/// logSet clauses joined by "and". Only accepted when both halves resolve to
/// a named exercise, so it never fires on delta idioms like "add two and a
/// half and do eight" (§4.5 pattern 4).
enum CompoundSplitPattern {
    static func match(_ words: [String], context: ParseContext) -> ParseResult? {
        guard let andIndex = splitIndex(words) else { return nil }
        let first = Array(words[..<andIndex])
        let second = Array(words[(andIndex + 1)...])
        guard let firstResult = clauseLogSet(first, context: context),
              let secondResult = clauseLogSet(second, context: context),
              hasExercise(firstResult), hasExercise(secondResult) else { return nil }
        return ParseResult(
            commands: firstResult.commands + secondResult.commands,
            confidence: min(firstResult.confidence, secondResult.confidence),
            matchedPattern: "compound"
        )
    }

    private static func splitIndex(_ words: [String]) -> Int? {
        for (index, word) in words.enumerated() where word == "and" {
            let previous = index > 0 ? words[index - 1] : ""
            let next = index + 1 < words.count ? words[index + 1] : ""
            if previous == "a" || previous == "an" || next == "a" || next == "an" { continue }
            return index
        }
        return nil
    }

    private static func clauseLogSet(_ words: [String], context: ParseContext) -> ParseResult? {
        MultiSetPattern.match(words, context: context) ?? SingleSetPattern.match(words, context: context)
    }

    private static func hasExercise(_ result: ParseResult) -> Bool {
        guard case .logSet(let spec) = result.commands.first, let exercise = spec.exercise
        else { return false }
        if case .onDeck = exercise { return false }
        return true
    }
}
