import Foundation

/// §4.5 pattern 9: "3 sets of 8 at 60", "5 by 5 at 120", "10, 10, 8 at 80".
enum MultiSetPattern {
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
        let setsCount = max(1, Int(setsMention.value))

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

        var excluded = NumberScan.consumedIndices(mentions)
        excluded.insert(setsIndex); excluded.insert(setsIndex + 1)
        if let atIndex { excluded.insert(atIndex) }
        let exercisePhrase = reps == nil ? ExercisePhrase.extract(words, excluding: excluded) : nil
        let exercise = ExercisePhrase.resolve(exercisePhrase, in: context)

        var unresolved: [Unresolved] = []
        if reps == nil { unresolved.append(.missingReps) }
        if case .spoken = exercise { unresolved.append(.exerciseAmbiguous) }

        let values = LogSetSpec.SetValues(reps: reps, weightKg: weightKg)
        let spec = LogSetSpec(exercise: exercise, sets: Array(repeating: values, count: setsCount))
        return ParseResult(
            commands: [.logSet(spec)], confidence: 0.88, matchedPattern: "multiSetOf",
            unresolved: unresolved
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
        let spec = LogSetSpec(
            sets: Array(repeating: values, count: max(1, Int(setsMention.value)))
        )
        return ParseResult(
            commands: [.logSet(spec)], confidence: 0.88, matchedPattern: "multiSetBy"
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
        let sets = repsRun.map { LogSetSpec.SetValues(reps: Int($0.value), weightKg: weightKg) }
        return ParseResult(
            commands: [.logSet(LogSetSpec(sets: sets))], confidence: 0.85,
            matchedPattern: "multiSetSequential"
        )
    }
}
