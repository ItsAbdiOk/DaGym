import Foundation

/// §4.5 pattern 12: "done" / "next" alone completes the on-deck set.
enum CompletionPattern {
    private static let words: Set<String> = ["done", "next", "tick", "it", "log"]

    static func match(_ tokens: [String]) -> ParseResult? {
        guard !tokens.isEmpty, tokens.allSatisfy({ words.contains($0) }) else { return nil }
        return ParseResult(commands: [.completeOnDeck], confidence: 0.9, matchedPattern: "completeOnDeck")
    }
}

/// §4.5 pattern 13: a bare number alone, capped at low confidence for a confirm card.
enum BareNumberPattern {
    static func match(_ words: [String]) -> ParseResult? {
        guard words.count <= 2, let (value, consumed) = NumberWords.parse(words, at: 0),
              consumed == words.count
        else {
            return nil
        }
        let isWeightLike = value > 50 || value != value.rounded()
        let values = isWeightLike
            ? LogSetSpec.SetValues(weightKg: value)
            : LogSetSpec.SetValues(reps: Int(value))
        return ParseResult(
            commands: [.logSet(LogSetSpec(sets: [values]))], confidence: 0.7, matchedPattern: "bareNumber"
        )
    }
}
