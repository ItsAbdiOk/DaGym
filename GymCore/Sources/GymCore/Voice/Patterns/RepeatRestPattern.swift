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

        let rest = Array(words[next...])
        if let repsIndex = rest.firstIndex(where: { $0 == "do" || $0 == "but" }),
           repsIndex + 1 < rest.count, let (value, _) = NumberWords.parse(rest, at: repsIndex + 1) {
            overrides.reps = Int(value)
        } else if rest.count <= 2, let (value, consumed) = NumberWords.parse(rest, at: 0),
                  consumed == rest.count {
            overrides.reps = Int(value)
        }
        return ParseResult(
            commands: [.repeatPrevious(overrides: overrides)], confidence: 0.9,
            matchedPattern: "repeat"
        )
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
            let seconds = words[unitIndex] == "minutes" || words[unitIndex] == "minute"
                ? Int(value * 60) : Int(value)
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
