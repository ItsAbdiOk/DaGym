import Foundation

/// §4.5 pattern 9: "3 sets of 8 at 60", "5 by 5 at 120", "10, 10, 8 at 80" —
/// each with an optional spoken exercise ("squats five by five at one forty").
enum MultiSetPattern {
    /// The most sets one utterance is ever materialised into. One above
    /// `LogCommandValidator`'s cap of 10, so "a thousand sets of eight" is still *rejected* by
    /// the validator (`.setsCountOutOfBounds`) rather than silently trimmed to ten — but
    /// "999999 sets of eight" no longer allocates a million `SetValues` on the way to that
    /// rejection.
    static let maxSpokenSets = 11

    /// `Array(repeating:count:)` for a spoken count, clamped to `maxSpokenSets`.
    static func repeated(_ values: LogSetSpec.SetValues, count: Double) -> [LogSetSpec.SetValues] {
        let clamped = count.isFinite ? min(max(1, count), Double(maxSpokenSets)) : 1
        return Array(repeating: values, count: Int(clamped))
    }

    static func match(_ words: [String], context: ParseContext) -> ParseResult? {
        if let result = setsOf(words, context: context) { return result }
        if let result = byForm(words, context: context) { return result }
        if let result = sequentialReps(words, context: context) { return result }
        return nil
    }

    /// "<n> sets of <reps|exercise> [at <weight>]"
    private static func setsOf(_ words: [String], context: ParseContext) -> ParseResult? {
        guard let setsIndex = words.firstIndex(where: { $0 == "sets" || $0 == "set" }) else { return nil }
        let mentions = NumberScan.scan(words)
        guard let setsMention = mentions.first(where: { $0.range.upperBound == setsIndex }),
              setsIndex + 1 < words.count, words[setsIndex + 1] == "of" else { return nil }

        let afterOf = setsIndex + 2
        let atIndex = words[afterOf...].firstIndex(of: "at")
        let midEnd = atIndex ?? words.count
        let midMentions = mentions.filter { $0.range.lowerBound >= afterOf && $0.range.upperBound <= midEnd }
        let reps = midMentions.first.map { Int($0.value) }

        var weightKg: Double?
        if let atIndex, atIndex + 1 < words.count,
           let weightMention = mentions.first(where: { $0.range.lowerBound == atIndex + 1 }) {
            weightKg = UnitParser.weightKg(
                number: weightMention.value, unit: weightMention.unit, context: context
            )
        }

        let values = LogSetSpec.SetValues(reps: reps, weightKg: weightKg)
        return result(
            words, sets: repeated(values, count: setsMention.value),
            confidence: 0.88, pattern: "multiSetOf", context: context
        )
    }

    /// "<sets> by <reps> [at <weight>]" — "5 by 5 at 120".
    private static func byForm(_ words: [String], context: ParseContext) -> ParseResult? {
        guard let byIndex = words.firstIndex(of: "by") else { return nil }
        let mentions = NumberScan.scan(words)
        guard let setsMention = mentions.first(where: { $0.range.upperBound == byIndex }),
              let repsMention = mentions.first(where: { $0.range.lowerBound == byIndex + 1 })
        else { return nil }
        var weightKg: Double?
        if let atIndex = words.firstIndex(of: "at"), atIndex >= repsMention.range.upperBound,
           let weightMention = mentions.first(where: { $0.range.lowerBound == atIndex + 1 }) {
            weightKg = UnitParser.weightKg(
                number: weightMention.value, unit: weightMention.unit, context: context
            )
        }
        let values = LogSetSpec.SetValues(reps: Int(repsMention.value), weightKg: weightKg)
        return result(
            words, sets: repeated(values, count: setsMention.value),
            confidence: 0.88, pattern: "multiSetBy", context: context
        )
    }

    /// "10, 10, 8 at 80" — a run of bare numbers, each its own set's reps, one shared weight.
    private static func sequentialReps(_ words: [String], context: ParseContext) -> ParseResult? {
        let mentions = NumberScan.scan(words)
        guard mentions.count >= 3 else { return nil }
        var runEnd = 1
        while runEnd < mentions.count - 1,
              mentions[runEnd].range.lowerBound == mentions[runEnd - 1].range.upperBound {
            runEnd += 1
        }
        guard runEnd >= 2 else { return nil }
        let repsRun = Array(mentions[0...(runEnd - 1)])
        let weightMention = mentions[runEnd]
        guard let atIndex = words.firstIndex(of: "at"),
              atIndex == weightMention.range.lowerBound - 1
        else { return nil }
        let weightKg = UnitParser.weightKg(
            number: weightMention.value, unit: weightMention.unit, context: context
        )
        let sets = repsRun.prefix(maxSpokenSets).map {
            LogSetSpec.SetValues(reps: Int($0.value), weightKg: weightKg)
        }
        return result(words, sets: sets, confidence: 0.85, pattern: "multiSetSequential", context: context)
    }

    /// Whatever is left once numbers and grammar words are gone names the exercise.
    private static func result(
        _ words: [String], sets: [LogSetSpec.SetValues], confidence: Double, pattern: String,
        context: ParseContext
    ) -> ParseResult {
        let numbers = NumberScan.consumedIndices(NumberScan.scan(words))
        let exercisePhrase = ExercisePhrase.extract(words, excluding: numbers)
        let (exercise, matchScore) = ExercisePhrase.resolve(exercisePhrase, in: context)

        var unresolved: [Unresolved] = []
        if sets.first?.reps == nil { unresolved.append(.missingReps) }
        if case .spoken = exercise { unresolved.append(.exerciseAmbiguous) }

        let spec = LogSetSpec(exercise: exercise, sets: sets)
        return ParseResult(
            commands: [.logSet(spec)], confidence: confidence * matchScore, matchedPattern: pattern,
            unresolved: unresolved
        )
    }
}
