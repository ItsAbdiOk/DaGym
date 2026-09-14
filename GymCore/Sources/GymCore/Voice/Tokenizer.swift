import Foundation

/// A unit a bare number can be tagged with.
public enum UnitKind: String, Equatable, Sendable {
    case kg, lb, plates, seconds, minutes
    /// Cardio distance: "five k", "3 miles".
    case km, miles
}

/// Normalises raw speech/typed text into the word array every pattern reads.
public enum Tokenizer {
    /// Multi-word phrase joins, longest-first, applied before tokenising.
    private static let phraseJoins: [(String, String)] = [
        ("per side", "per-side"), ("each arm", "per-side"), ("each side", "per-side"),
        ("per arm", "per-side"), ("each leg", "per-side"), ("per leg", "per-side"),
        ("in the tank", "in-the-tank"), ("reps in reserve", "in-the-tank"),
        ("same again", "same-again"), ("same weight", "same-weight"), ("same thing", "same-again"),
        ("rest pause", "rest-pause"), ("drop set", "drop-set"), ("warm up", "warm-up"),
        ("pull ups", "pull-ups"), ("pull up", "pull-up"), ("chin ups", "pull-ups"),
        ("scrap that", "scrap-that"), ("take that back", "scrap-that"),
        ("delete the last set", "delete-last-set"), ("delete last set", "delete-last-set"),
        ("rest timer", "rest-timer"), ("last time", "last-time"), ("last session", "last-time"),
        ("my pr", "my-pr"), ("personal record", "my-pr"),
        ("nothing left", "nothing-left"), ("all out", "all-out")
    ]

    /// Lowercase, drop possessive/contraction "'s", strip punctuation (a `.`
    /// survives only between digits, so "102.5" stays a number and "hundred."
    /// does not become a word), map Unicode fractions and "×", collapse
    /// whitespace, and join known multi-word phrases.
    public static func normalize(_ text: String) -> String {
        var lowered = text.lowercased()
        lowered = lowered.replacingOccurrences(of: "½", with: " and a half")
        lowered = lowered.replacingOccurrences(of: "¼", with: " and a quarter")
        lowered = lowered.replacingOccurrences(of: "×", with: " x ")
        lowered = lowered.replacingOccurrences(of: "'s", with: "")
        lowered = lowered.replacingOccurrences(of: "’s", with: "")
        let scalars = Array(lowered.unicodeScalars)
        var stripped = ""
        for (index, scalar) in scalars.enumerated() {
            if scalar == "." || scalar == "," {
                let previousIsDigit = index > 0 && CharacterSet.decimalDigits.contains(scalars[index - 1])
                let nextIsDigit = index + 1 < scalars.count
                    && CharacterSet.decimalDigits.contains(scalars[index + 1])
                stripped.append(previousIsDigit && nextIsDigit && scalar == "." ? "." : " ")
            } else if scalar == "-" || scalar == "/" || CharacterSet.alphanumerics.contains(scalar) {
                stripped.unicodeScalars.append(scalar)
            } else {
                stripped.append(" ")
            }
        }
        var joined = stripped
        for (phrase, token) in phraseJoins {
            joined = joined.replacingOccurrences(of: phrase, with: token)
        }
        let components = joined.split(separator: " ").map(String.init)
        return components.joined(separator: " ")
    }

    /// Splits normalised text into raw words (phrases already joined), then
    /// unglues typed shorthand: "5x5" → 5 by 5, "100kg" → 100 kg, "ninety-five"
    /// → ninety five, a lone "x" → "by".
    public static func words(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init).flatMap(unglued)
    }

    private static func unglued(_ word: String) -> [String] {
        if word == "x" { return ["by"] }
        if word == "-" || word == "/" { return [] }
        if let hyphenated = NumberWords.hyphenatedNumberWords(word) { return hyphenated }
        if let parts = gluedShorthand(word) { return parts }
        return [word]
    }

    private static func gluedShorthand(_ word: String) -> [String]? {
        let scalars = Array(word.unicodeScalars)
        guard let first = scalars.first, CharacterSet.decimalDigits.contains(first) else { return nil }
        var index = 0
        while index < scalars.count,
              CharacterSet.decimalDigits.contains(scalars[index]) || scalars[index] == "." {
            index += 1
        }
        guard index < scalars.count else { return nil }
        let number = String(String.UnicodeScalarView(scalars[..<index]))
        let tail = String(String.UnicodeScalarView(scalars[index...]))
        if tail.hasPrefix("x"), let rest = gluedShorthand(String(tail.dropFirst())) ?? bareDigits(tail) {
            return [number, "by"] + rest
        }
        if unitKind(for: tail) != nil { return [number, tail] }
        return nil
    }

    private static func bareDigits(_ tail: String) -> [String]? {
        let digits = String(tail.dropFirst())
        guard !digits.isEmpty, digits.unicodeScalars.allSatisfy({
            CharacterSet.decimalDigits.contains($0) || $0 == "."
        }) else { return nil }
        return [digits]
    }

    /// Maps a bare word to the unit it names, if any.
    static func unitKind(for word: String) -> UnitKind? {
        switch word {
        case "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms": return .kg
        case "lb", "lbs", "pound", "pounds": return .lb
        case "plate", "plates": return .plates
        case "second", "seconds", "secs", "sec": return .seconds
        case "minute", "minutes", "min", "mins": return .minutes
        case "k", "km", "kms", "kilometer", "kilometers", "kilometre", "kilometres": return .km
        case "mi", "mile", "miles": return .miles
        default: return nil
        }
    }
}
