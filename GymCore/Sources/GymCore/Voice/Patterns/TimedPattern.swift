import Foundation

/// §4.5 pattern 10: timed holds, triggered by "held/hold/plank/hang" or an
/// on-deck exercise whose logging style is `.timedHold`.
enum TimedPattern {
    private static let triggerWords: Set<String> = ["held", "hold", "plank", "hang", "hanging"]
    /// Trigger words that only describe the hold; "plank"/"hang" name the exercise and stay.
    private static let grammarWords: Set<String> = ["held", "hold", "the", "for"]

    static func match(_ words: [String], context: ParseContext) -> ParseResult? {
        let isTimedContext = context.onDeck?.loggingStyle == .timedHold
        guard isTimedContext || !words.filter({ triggerWords.contains($0) }).isEmpty else { return nil }
        guard let (seconds, range) = DurationPattern.parse(words) else { return nil }

        var excluded = Set(range)
        for index in words.indices where grammarWords.contains(words[index]) {
            excluded.insert(index)
        }
        let exercisePhrase = ExercisePhrase.extract(words, excluding: excluded)
        let (exercise, matchScore) = ExercisePhrase.resolve(exercisePhrase, in: context)
        var unresolved: [Unresolved] = []
        if case .spoken = exercise { unresolved.append(.exerciseAmbiguous) }

        let values = LogSetSpec.SetValues(durationSeconds: seconds)
        let spec = LogSetSpec(exercise: exercise, sets: [values])
        return ParseResult(
            commands: [.logSet(spec)], confidence: 0.9 * matchScore, matchedPattern: "timed",
            unresolved: unresolved
        )
    }
}
