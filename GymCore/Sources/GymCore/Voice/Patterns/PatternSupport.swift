import Foundation

/// Numbers the grammar shares, so each cutoff lives in one place.
enum VoiceGrammar {
    /// A bare number at or below this is a rep count, above it a weight. Fifty-rep
    /// sets are legal, but nobody says "fifty" for reps without the word "reps".
    static let repsWeightCutoff = 50.0
    /// The RPE scale as spoken. `Effort` clamps into it, so out-of-range numbers
    /// have to be refused before an `Effort` is made.
    static let rpeRange = 5.0...10.0
    /// Reps-in-reserve as spoken: the RPE scale mirrored.
    static let rirRange = 0.0...5.0
}

/// Detects and locates the joined set-kind word in a word array.
enum SetKindWord {
    static func detect(_ words: [String]) -> (kind: SetKind, index: Int)? {
        if let idx = words.firstIndex(of: "warm-up") { return (.warmup, idx) }
        if let idx = words.firstIndex(of: "amrap") { return (.amrap, idx) }
        if let idx = words.firstIndex(of: "drop-set") { return (.drop, idx) }
        if let idx = words.firstIndex(of: "failure") { return (.failure, idx) }
        if let idx = words.firstIndex(of: "to-failure") { return (.failure, idx) }
        if let idx = words.firstIndex(of: "rest-pause") { return (.restPause, idx) }
        return nil
    }
}

/// Builds the leftover exercise phrase once numbers and grammar keywords are
/// stripped out of a word array.
enum ExercisePhrase {
    static let stopWords: Set<String> = [
        "at", "to", "for", "got", "by", "reps", "rep", "a", "an", "the", "and", "do",
        "but", "of", "sets", "set", "no", "not", "same-again", "same-weight", "again",
        "undo", "done", "next", "note", "what", "did", "i", "last-time", "my-pr", "in",
        "start", "add", "up", "drop"
    ]

    /// Words a lifter says around a set that never name an exercise (§4.8:
    /// ignored, no penalty).
    static let fillerWords: Set<String> = [
        "just", "ok", "okay", "so", "um", "erm", "uh", "er", "like", "yeah", "then", "that",
        "was", "it", "please", "went", "go", "is", "my", "with"
    ]

    static func extract(_ words: [String], excluding: Set<Int>) -> String? {
        let leftover = words.enumerated()
            .filter {
                !excluding.contains($0.offset) && !stopWords.contains($0.element)
                    && !fillerWords.contains($0.element)
            }
            .map(\.element)
        return leftover.isEmpty ? nil : leftover.joined(separator: " ")
    }

    /// Resolves a spoken phrase to an `ExerciseRef` and the match score to fold
    /// into confidence; `nil` ref (→ on-deck) at score 1 when nothing was left to resolve.
    static func resolve(_ phrase: String?, in context: ParseContext) -> (ref: ExerciseRef?, score: Double) {
        guard let phrase else { return (nil, 1) }
        if phrase == "this" { return (.onDeck, 1) }
        let scored = ExerciseMatcher.resolveScored(phrase, in: context)
        return (scored.ref, scored.score)
    }
}

/// Finds a spoken duration ("a minute", "one minute twenty", "a minute and a
/// half", "ninety seconds").
enum DurationPattern {
    static func parse(_ words: [String]) -> (seconds: Int, range: ClosedRange<Int>)? {
        for wordIdx in words.indices where words[wordIdx] == "minute" || words[wordIdx] == "minutes" {
            guard wordIdx > 0, words[wordIdx - 1] == "a" || words[wordIdx - 1] == "an" else { continue }
            var seconds = 60
            var end = wordIdx
            if let (value, consumed) = NumberWords.parse(words, at: wordIdx + 1) {
                seconds += Int(value)
                end = wordIdx + consumed
            } else if let (fraction, consumed) = NumberWords.andAFraction(words, at: wordIdx + 1) {
                seconds += Int(fraction * 60)
                end = wordIdx + consumed
            }
            return (seconds, (wordIdx - 1)...end)
        }
        let mentions = NumberScan.scan(words)
        for (index, mention) in mentions.enumerated() {
            if mention.unit == .minutes {
                var seconds = UnitParser.durationSeconds(number: mention.value, unit: .minutes)
                var endIndex = mention.range.upperBound - 1
                if index + 1 < mentions.count, mentions[index + 1].unit == nil,
                   mentions[index + 1].range.lowerBound == mention.range.upperBound {
                    seconds += Int(mentions[index + 1].value)
                    endIndex = mentions[index + 1].range.upperBound - 1
                } else if let (fraction, consumed) = NumberWords.andAFraction(
                    words, at: mention.range.upperBound
                ) {
                    seconds += Int(fraction * 60)
                    endIndex = mention.range.upperBound + consumed - 1
                }
                return (seconds, mention.range.lowerBound...endIndex)
            }
            if mention.unit == .seconds {
                return (Int(mention.value), mention.range.lowerBound...(mention.range.upperBound - 1))
            }
        }
        return nil
    }
}
