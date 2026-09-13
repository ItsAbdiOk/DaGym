import Foundation

/// §4.5 pattern 4: "same again [but …]", plus the standalone delta idioms
/// "add two and a half", "up two point five", "drop five".
enum RepeatPattern {
    static func match(_ words: [String], context: ParseContext) -> ParseResult? {
        guard let first = words.first else { return nil }
        var overrides = LogSetSpec.Overrides()
        var next = 1

        if first == "same-again" || first == "repeat" || first == "again" {
            // no delta
        } else if first == "same-weight" {
            // reps-only override follows
        } else if first == "add" || first == "up",
                  let delta = deltaAfterTrigger(words, sign: 1, context: context) {
            overrides.weightDeltaKg = delta.value; next = delta.consumed
        } else if first == "drop", words.count > 1, words[1] != "to",
                  let delta = deltaAfterTrigger(words, sign: -1, context: context) {
            overrides.weightDeltaKg = delta.value; next = delta.consumed
        } else {
            return nil
        }

        assignOverrides(Array(words[next...]), to: &overrides, context: context)
        return ParseResult(
            commands: [.repeatPrevious(overrides: overrides)], confidence: 0.9,
            matchedPattern: "repeat"
        )
    }

    /// "but seven reps" / "but at ninety" / "with ninety kilos" / "nine": a number
    /// after the trigger is a weight when it carries a unit, follows "at"/"with",
    /// or is too big to be reps; otherwise it is the rep count.
    private static func assignOverrides(
        _ rest: [String], to overrides: inout LogSetSpec.Overrides, context: ParseContext
    ) {
        for mention in NumberScan.scan(rest) {
            let precededByAt = mention.range.lowerBound > 0
                && ["at", "with"].contains(rest[mention.range.lowerBound - 1])
            let followsReps = NumberWords.repsFollows(rest, at: mention.range.upperBound)
            let isWeight = !followsReps
                && (mention.unit != nil || precededByAt || mention.value > VoiceGrammar.repsWeightCutoff)
            if isWeight, overrides.weightKg == nil {
                overrides.weightKg = UnitParser.weightKg(
                    number: mention.value, unit: mention.unit, context: context
                )
            } else if !isWeight, overrides.reps == nil {
                overrides.reps = Int(mention.value)
            }
        }
    }

    /// Bails out when the number is actually a rest-timer duration ("add thirty seconds").
    private static func deltaAfterTrigger(
        _ words: [String], sign: Double, context: ParseContext
    ) -> (value: Double, consumed: Int)? {
        guard words.count > 1, let (value, consumed) = NumberWords.parse(words, at: 1)
        else { return nil }
        let tailIndex = 1 + consumed
        if tailIndex < words.count, words[tailIndex] == "seconds" || words[tailIndex] == "second"
            || words[tailIndex] == "minutes" || words[tailIndex] == "minute" { return nil }
        return (sign * context.unit.toKg(value), 1 + consumed)
    }
}

/// §4.5 pattern 5: the rest timer.
enum RestPattern {
    private static let triggers: Set<String> = ["rest", "rest-timer", "timer", "skip"]

    static func match(_ words: [String]) -> ParseResult? {
        if words.first == "add", words.count > 1,
           let (value, consumed) = NumberWords.parse(words, at: 1) {
            let unitIndex = 1 + consumed
            guard unitIndex < words.count,
                  ["seconds", "second", "minutes", "minute"].contains(words[unitIndex])
            else { return nil }
            let seconds = UnitParser.durationSeconds(
                number: value, unit: Tokenizer.unitKind(for: words[unitIndex])
            )
            return ParseResult(
                commands: [.rest(.adjust(deltaSeconds: seconds))], confidence: 0.9,
                matchedPattern: "restAdjust"
            )
        }
        guard words.contains(where: { triggers.contains($0) }) else { return nil }
        if words.contains("skip") {
            return ParseResult(
                commands: [.rest(.skip)], confidence: 0.9, matchedPattern: "restSkip"
            )
        }
        if let (seconds, _) = DurationPattern.parse(words) {
            return ParseResult(
                commands: [.rest(.start(seconds: seconds))], confidence: 0.9,
                matchedPattern: "restStart"
            )
        }
        return ParseResult(
            commands: [.rest(.start(seconds: nil))], confidence: 0.95,
            matchedPattern: "restStartBare"
        )
    }
}
