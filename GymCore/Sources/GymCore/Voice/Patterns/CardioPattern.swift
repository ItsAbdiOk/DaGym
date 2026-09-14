import Foundation

/// Cardio sets: "five k in twenty five thirty", "ran 3 miles in 28 minutes", "rowed 2000
/// metres". Fires on a distance unit, a cardio verb, or an on-deck exercise logged as cardio,
/// and fills `distanceMeters`/`durationSeconds` — never reps or load.
enum CardioPattern {
    private static let triggerWords: Set<String> = [
        "ran", "rowed", "cycled", "walked", "jogged", "swam", "biked", "hiked", "skied"
    ]
    /// Words that only describe the effort; an exercise name ("row", "run") is never in here.
    private static let grammarWords: Set<String> = triggerWords.union(["in", "for", "did", "at", "time"])

    static func match(_ words: [String], context: ParseContext) -> ParseResult? {
        let mentions = NumberScan.scan(words)
        let distance = mentions.first { $0.unit == .km || $0.unit == .miles }
        let isCardioContext = context.onDeck?.loggingStyle == .cardio
        let hasTrigger = words.contains { triggerWords.contains($0) }
        guard distance != nil || isCardioContext || hasTrigger else { return nil }

        var excluded = Set<Int>()
        var distanceMeters: Double?
        if let distance {
            distanceMeters = UnitParser.distanceMeters(number: distance.value, unit: distance.unit)
            excluded.formUnion(distance.range)
        }
        let duration = DurationPattern.parse(words) ?? clockDuration(mentions, excluding: excluded)
        if let duration { excluded.formUnion(duration.range) }
        guard distanceMeters != nil || duration != nil else { return nil }
        // A number this grammar can't place ("eight at sixty" on a treadmill row) is not a run;
        // let the set patterns read it and the validator refuse it.
        guard mentions.allSatisfy({ excluded.isSuperset(of: $0.range) }) else { return nil }

        for index in words.indices where grammarWords.contains(words[index]) { excluded.insert(index) }
        let exercisePhrase = ExercisePhrase.extract(words, excluding: excluded)
        let (exercise, matchScore) = ExercisePhrase.resolve(exercisePhrase, in: context)
        var unresolved: [Unresolved] = []
        if case .spoken = exercise { unresolved.append(.exerciseAmbiguous) }

        let values = LogSetSpec.SetValues(durationSeconds: duration?.seconds, distanceMeters: distanceMeters)
        return ParseResult(
            commands: [.logSet(LogSetSpec(exercise: exercise, sets: [values]))],
            confidence: 0.9 * matchScore, matchedPattern: "cardio", unresolved: unresolved
        )
    }

    /// "in twenty five thirty" / "in 25 30": two bare numbers read as minutes then seconds, one
    /// bare number as minutes. Only unit-less mentions outside the distance qualify, so "five k"
    /// is never mistaken for five minutes.
    private static func clockDuration(
        _ mentions: [NumberMention], excluding: Set<Int>
    ) -> (seconds: Int, range: ClosedRange<Int>)? {
        let bare = mentions.filter { $0.unit == nil && excluding.isDisjoint(with: $0.range) }
        guard let minutes = bare.first else { return nil }
        var seconds = Int(minutes.value.rounded()) * 60
        var end = minutes.range.upperBound - 1
        if bare.count > 1, bare[1].range.lowerBound == minutes.range.upperBound, bare[1].value < 60 {
            seconds += Int(bare[1].value.rounded())
            end = bare[1].range.upperBound - 1
        }
        guard seconds > 0 else { return nil }
        return (seconds, minutes.range.lowerBound...end)
    }
}
