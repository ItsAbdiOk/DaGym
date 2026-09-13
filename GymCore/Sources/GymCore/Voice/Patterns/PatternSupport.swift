import Foundation

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
        "at", "to", "for", "got", "by", "x", "reps", "rep", "a", "an", "the", "and", "do",
        "but", "of", "sets", "set", "no", "not", "same-again", "same-weight", "again",
        "undo", "done", "next", "note", "what", "did", "i", "last-time", "my-pr", "in",
        "start", "add", "up", "drop"
    ]

    static func extract(_ words: [String], excluding: Set<Int>) -> String? {
        let leftover = words.enumerated()
            .filter { !excluding.contains($0.offset) && !stopWords.contains($0.element) }
            .map(\.element)
        return leftover.isEmpty ? nil : leftover.joined(separator: " ")
    }

    /// Resolves a spoken phrase to an `ExerciseRef`, or `nil` (→ on-deck) if
    /// nothing was left to resolve.
    static func resolve(_ phrase: String?, in context: ParseContext) -> ExerciseRef? {
        guard let phrase, phrase != "this" else { return phrase == "this" ? .onDeck : nil }
        return ExerciseMatcher.resolve(phrase, in: context)
    }
}

/// Finds a spoken duration ("a minute", "one minute twenty", "ninety seconds").
enum DurationPattern {
    static func parse(_ words: [String]) -> (seconds: Int, range: ClosedRange<Int>)? {
        for wordIdx in words.indices where words[wordIdx] == "minute" || words[wordIdx] == "minutes" {
            guard wordIdx > 0, words[wordIdx - 1] == "a" || words[wordIdx - 1] == "an" else { continue }
            var seconds = 60
            var end = wordIdx
            if wordIdx + 1 < words.count, let (value, consumed) = NumberWords.parse(words, at: wordIdx + 1) {
                seconds += Int(value)
                end = wordIdx + consumed
            }
            return (seconds, (wordIdx - 1)...end)
        }
        let mentions = NumberScan.scan(words)
        for (index, mention) in mentions.enumerated() {
            if mention.unit == .minutes {
                var seconds = Int((mention.value * 60).rounded())
                var endIndex = mention.range.upperBound - 1
                if index + 1 < mentions.count, mentions[index + 1].unit == nil,
                   mentions[index + 1].range.lowerBound == mention.range.upperBound {
                    seconds += Int(mentions[index + 1].value)
                    endIndex = mentions[index + 1].range.upperBound - 1
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
