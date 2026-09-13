import Foundation

/// §4.5 patterns 1–3: undo, correction of the last set, and rating the last set.
enum MetaCorrectionRate {
    private static let undoWords: Set<String> = ["undo", "scrap-that", "delete-last-set"]
    private static let correctionTriggers: Set<String> = ["no", "actually", "correction", "sorry"]

    static func matchUndo(_ words: [String]) -> ParseResult? {
        guard let first = words.first, undoWords.contains(first) else { return nil }
        return ParseResult(commands: [.undo], confidence: 0.95, matchedPattern: "undo")
    }

    static func matchCorrection(_ words: [String], context: ParseContext) -> ParseResult? {
        guard let first = words.first, correctionTriggers.contains(first) else { return nil }
        let rest = Array(words.dropFirst())
        let mentions = NumberScan.scan(rest)
        guard !mentions.isEmpty else { return nil }

        var overrides = LogSetSpec.Overrides()
        if let notIndex = rest.firstIndex(of: "not"),
           let before = mentions.last(where: { $0.range.upperBound <= notIndex }) {
            assign(before, to: &overrides, context: context)
        } else if let mention = mentions.first {
            assign(mention, to: &overrides, context: context)
        }
        return ParseResult(
            commands: [.correctLastSet(overrides)], confidence: 0.9, matchedPattern: "correction"
        )
    }

    private static func assign(
        _ mention: NumberMention, to overrides: inout LogSetSpec.Overrides,
        context: ParseContext
    ) {
        if mention.unit != nil || mention.value > VoiceGrammar.repsWeightCutoff {
            overrides.weightKg = UnitParser.weightKg(
                number: mention.value, unit: mention.unit, context: context
            )
        } else {
            overrides.reps = Int(mention.value)
        }
    }

    /// An utterance that starts by changing the session is never a rating, even
    /// when a phrase-table word appears later ("add easy bar curls").
    private static let sessionEditTriggers: Set<String> = [
        "add", "swap", "switch", "replace", "change", "remove", "drop", "note"
    ]

    static func matchRateLastSet(_ words: [String]) -> ParseResult? {
        if let first = words.first, sessionEditTriggers.contains(first) { return nil }
        if EffortExtraction.hasOutOfRangeNumber(words) {
            return ParseResult(matchedPattern: "rateLastSet", unresolved: [.effortOutOfRange])
        }
        guard let (effort, range) = EffortExtraction.extract(words) else { return nil }
        var remaining = words
        remaining.removeSubrange(range)
        let otherMentions = NumberScan.scan(remaining)
        guard otherMentions.isEmpty else { return nil }
        return ParseResult(commands: [.rateLastSet(effort)], confidence: 0.9, matchedPattern: "rateLastSet")
    }
}
