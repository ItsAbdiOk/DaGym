import Foundation

/// One number found while scanning a word array, with its attached unit (if any).
struct NumberMention {
    var value: Double
    var unit: UnitKind?
    var range: Range<Int>
}

/// Scans a normalised word array for number mentions, preferring plate
/// phrases ("a plate and a half") over plain number-word runs.
enum NumberScan {
    static func scan(_ words: [String]) -> [NumberMention] {
        var mentions: [NumberMention] = []
        var idx = 0
        while idx < words.count {
            if let plate = UnitParser.platePhrase(words, at: idx) {
                mentions.append(NumberMention(
                    value: plate.perSide, unit: .plates, range: idx..<(idx + plate.consumed)
                ))
                idx += plate.consumed
                continue
            }
            if let (value, consumed) = NumberWords.parse(words, at: idx), consumed > 0 {
                var end = idx + consumed
                var unit: UnitKind?
                if end < words.count, let attached = Tokenizer.unitKind(for: words[end]) {
                    unit = attached
                    end += 1
                }
                mentions.append(NumberMention(value: value, unit: unit, range: idx..<end))
                idx = end
                continue
            }
            idx += 1
        }
        return mentions
    }

    /// Indices in `words` that some mention (or its unit tag) occupies.
    static func consumedIndices(_ mentions: [NumberMention]) -> Set<Int> {
        var result = Set<Int>()
        for mention in mentions { result.formUnion(mention.range) }
        return result
    }
}
