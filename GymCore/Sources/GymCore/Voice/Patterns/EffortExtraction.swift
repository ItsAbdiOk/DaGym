import Foundation

/// Finds a spoken effort rating (RPE/RIR or a phrase-table word) in a word array.
enum EffortExtraction {
    /// Words that, alone, imply a maximal or easy effort when no number is given.
    private static let maxEffortWords: Set<String> = ["grind", "maxed", "nothing-left", "all-out"]
    private static let easyEffortWords: Set<String> = ["easy", "smooth"]

    static func extract(_ words: [String]) -> (effort: Effort, range: Range<Int>)? {
        if let found = keywordEffort(words, keyword: "rpe", make: { Effort(rpe: $0) }) { return found }
        if let found = keywordEffort(words, keyword: "rir", make: { Effort(rir: Int($0)) }) { return found }
        if let found = inTheTankEffort(words) { return found }
        if let found = feltLikeEffort(words) { return found }
        if let found = atEffort(words) { return found }
        if let word = words.first(where: { maxEffortWords.contains($0) }),
           let idx = words.firstIndex(of: word) {
            return (Effort(rpe: 10), idx..<(idx + 1))
        }
        if let word = words.first(where: { easyEffortWords.contains($0) }),
           let idx = words.firstIndex(of: word) {
            return (Effort(rpe: 6), idx..<(idx + 1))
        }
        return nil
    }

    private static func keywordEffort(
        _ words: [String],
        keyword: String,
        make: (Double) -> Effort
    ) -> (Effort, Range<Int>)? {
        guard let idx = words.firstIndex(of: keyword), idx + 1 < words.count,
              let (value, consumed) = NumberWords.parse(words, at: idx + 1) else { return nil }
        return (make(value), idx..<(idx + 1 + consumed))
    }

    /// "two in the tank" — the number sits immediately before the joined phrase.
    private static func inTheTankEffort(_ words: [String]) -> (Effort, Range<Int>)? {
        guard let idx = words.firstIndex(of: "in-the-tank") else { return nil }
        let mentions = NumberScan.scan(words)
        guard let mention = mentions.last(where: { $0.range.upperBound == idx }) else { return nil }
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
        guard let (value, consumed) = NumberWords.parse(words, at: numberIndex), value >= 5, value <= 10
        else { return nil }
        return (Effort(rpe: value), idx..<(numberIndex + consumed))
    }

    /// "at an eight" / "at a nine out of ten" — restricted to the 5...10 RPE range
    /// so it never steals a weight number like "at a hundred".
    private static func atEffort(_ words: [String]) -> (Effort, Range<Int>)? {
        guard let idx = words.firstIndex(of: "at"), idx + 1 < words.count else { return nil }
        var numberIndex = idx + 1
        if words[numberIndex] == "a" || words[numberIndex] == "an" { numberIndex += 1 }
        guard let (value, consumed) = NumberWords.parse(words, at: numberIndex), value >= 5, value <= 10
        else { return nil }
        var end = numberIndex + consumed
        if end + 2 < words.count, words[end] == "out", words[end + 1] == "of" { end += 3 }
        return (Effort(rpe: value), idx..<end)
    }
}
