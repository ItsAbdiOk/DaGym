import Foundation

/// "bench eight at a hundred and rows eight at seventy [and curls ten at
/// twenty]" — independent logSet clauses joined by "and". Only accepted when
/// every clause resolves to a named exercise, so it never fires on delta
/// idioms like "add two and a half and do eight" (§4.5 pattern 4).
enum CompoundSplitPattern {
    static func match(_ words: [String], context: ParseContext) -> ParseResult? {
        let clauses = split(words)
        guard clauses.count >= 2 else { return nil }
        var commands: [LogCommand] = []
        var unresolved: [Unresolved] = []
        var confidence = 1.0
        for clause in clauses {
            guard let result = clauseLogSet(clause, context: context), hasExercise(result) else { return nil }
            commands.append(contentsOf: result.commands)
            unresolved.append(contentsOf: result.unresolved)
            confidence = min(confidence, result.confidence)
        }
        return ParseResult(
            commands: commands, confidence: confidence, matchedPattern: "compound", unresolved: unresolved
        )
    }

    /// Splits on every "and" that joins clauses, leaving alone the ones inside a
    /// number ("a hundred and five", "two and a half").
    private static func split(_ words: [String]) -> [[String]] {
        var clauses: [[String]] = []
        var current: [String] = []
        for (index, word) in words.enumerated() {
            if word == "and", !joinsNumber(words, at: index) {
                clauses.append(current)
                current = []
            } else {
                current.append(word)
            }
        }
        clauses.append(current)
        return clauses
    }

    private static func joinsNumber(_ words: [String], at index: Int) -> Bool {
        let previous = index > 0 ? words[index - 1] : ""
        let next = index + 1 < words.count ? words[index + 1] : ""
        if previous == "a" || previous == "an" || next == "a" || next == "an" { return true }
        if previous == "hundred" || previous == "thousand", NumberWords.parse(words, at: index + 1) != nil {
            return true
        }
        return false
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
