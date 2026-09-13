import Foundation

/// Finds a spoken effort rating (RPE/RIR or a phrase-table word) in a word array.
enum EffortExtraction {
    /// Words that, alone, imply a maximal or easy effort when no number is given.
    private static let maxEffortWords: Set<String> = ["grind", "maxed", "nothing-left", "all-out"]
    private static let easyEffortWords: Set<String> = ["easy", "smooth"]

    static func extract(_ words: [String]) -> (effort: Effort, range: Range<Int>)? {
        if let found = keywordEffort(words, keyword: "rpe", range: VoiceGrammar.rpeRange,
                                     make: { Effort(rpe: $0) }) { return found }
        if let found = keywordEffort(words, keyword: "rir", range: VoiceGrammar.rirRange,
                                     make: { Effort(rir: Int($0)) }) { return found }
        if let found = inTheTankEffort(words) { return found }
        if let found = feltLikeEffort(words) { return found }
        if let found = atEffort(words) { return found }
        if let idx = phraseWordIndex(words, in: maxEffortWords) { return (Effort(rpe: 10), idx..<(idx + 1)) }
        if let idx = phraseWordIndex(words, in: easyEffortWords) { return (Effort(rpe: 6), idx..<(idx + 1)) }
        return nil
    }

    /// True when the utterance rates effort with a number outside the scale
    /// ("rpe three", "six in the tank") — nothing else in it will parse, and the
    /// user should be told why rather than get a silently clamped RPE.
    static func hasOutOfRangeNumber(_ words: [String]) -> Bool {
        for (keyword, range) in [("rpe", VoiceGrammar.rpeRange), ("rir", VoiceGrammar.rirRange)] {
            if let idx = words.firstIndex(of: keyword),
               let (value, _) = NumberWords.parse(words, at: idx + 1), !range.contains(value) {
                return true
            }
        }
        if let idx = words.firstIndex(of: "in-the-tank"),
           let mention = NumberScan.scan(words).last(where: { $0.range.upperBound == idx }),
           !VoiceGrammar.rirRange.contains(mention.value) {
            return true
        }
        return false
    }

    /// "easy bar curls" is EZ-bar work, not an RPE 6: a phrase-table word only
    /// counts when "bar" does not follow it.
    private static func phraseWordIndex(_ words: [String], in table: Set<String>) -> Int? {
        guard let idx = words.firstIndex(where: { table.contains($0) }) else { return nil }
        if idx + 1 < words.count, words[idx + 1] == "bar" { return nil }
        return idx
    }

    private static func keywordEffort(
        _ words: [String],
        keyword: String,
        range: ClosedRange<Double>,
        make: (Double) -> Effort
    ) -> (Effort, Range<Int>)? {
        guard let idx = words.firstIndex(of: keyword),
              let (value, consumed) = NumberWords.parse(words, at: idx + 1), range.contains(value)
        else { return nil }
        return (make(value), idx..<(idx + 1 + consumed))
    }

    /// "two in the tank" — the number sits immediately before the joined phrase.
    private static func inTheTankEffort(_ words: [String]) -> (Effort, Range<Int>)? {
        guard let idx = words.firstIndex(of: "in-the-tank") else { return nil }
        let mentions = NumberScan.scan(words)
        guard let mention = mentions.last(where: { $0.range.upperBound == idx }),
              VoiceGrammar.rirRange.contains(mention.value) else { return nil }
        return (Effort(rir: Int(mention.value)), mention.range.lowerBound..<(idx + 1))
    }

    /// "felt like a nine" / "felt like an eight".
    private static func feltLikeEffort(_ words: [String]) -> (Effort, Range<Int>)? {
        guard let idx = words.firstIndex(of: "felt"), idx + 1 < words.count, words[idx + 1] == "like"
        else { return nil }
        var numberIndex = idx + 2
        if numberIndex < words.count, words[numberIndex] == "a" || words[numberIndex] == "an" {
            numberIndex += 1
        }
        guard let (value, consumed) = NumberWords.parse(words, at: numberIndex),
              VoiceGrammar.rpeRange.contains(value)
        else { return nil }
        return (Effort(rpe: value), idx..<(numberIndex + consumed))
    }

    /// "at an eight" / "at a nine out of ten". The article is required: a bare
    /// "at ten" after a rep count is a weight ("lateral raises twelve at ten").
    private static func atEffort(_ words: [String]) -> (Effort, Range<Int>)? {
        for idx in words.indices where words[idx] == "at" {
            guard idx + 2 < words.count, words[idx + 1] == "a" || words[idx + 1] == "an" else { continue }
            let numberIndex = idx + 2
            guard let (value, consumed) = NumberWords.parse(words, at: numberIndex),
                  VoiceGrammar.rpeRange.contains(value)
            else { continue }
            var end = numberIndex + consumed
            if end + 2 < words.count, words[end] == "out", words[end + 1] == "of" { end += 3 }
            return (Effort(rpe: value), idx..<end)
        }
        return nil
    }
}
