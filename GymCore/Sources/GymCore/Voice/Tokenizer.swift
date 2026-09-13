import Foundation

/// One tagged piece of a normalised utterance.
public enum Token: Equatable, Sendable {
    case number(Double)
    case unit(UnitKind)
    case keyword(String)
    case word(String)
}

/// A unit a bare number can be tagged with.
public enum UnitKind: String, Equatable, Sendable {
    case kg, lb, plates, seconds, minutes
}

/// Normalises raw speech/typed text and turns it into `[Token]`.
public enum Tokenizer {
    /// Known keywords the parser's patterns look for.
    static let keywords: Set<String> = [
        "reps", "rep", "sets", "set", "at", "for", "by", "of", "rpe", "rir", "same", "but",
        "swap", "switch", "replace", "change", "per", "side", "each", "arm", "arms", "drop",
        "minus", "plus", "add", "up", "to", "and", "no", "actually", "correction", "sorry",
        "not", "again", "note", "undo", "done", "next", "held", "hold", "rest", "timer",
        "skip", "warm", "amrap", "failure", "pause", "bodyweight", "assisted", "with",
        "felt", "like", "tank", "reserve", "left", "in", "the", "out", "got", "remove",
        "swapped", "started", "start", "what", "did", "i", "last", "time", "session",
        "pr", "best", "scrap", "that", "this", "take", "back", "tick", "it", "log", "got",
        "start", "did", "do", "held", "hold", "got"
    ]

    /// Multi-word phrase joins, longest-first, applied before tokenising.
    private static let phraseJoins: [(String, String)] = [
        ("per side", "per-side"), ("each arm", "per-side"), ("each side", "per-side"),
        ("in the tank", "in-the-tank"), ("reps in reserve", "in-the-tank"),
        ("same again", "same-again"), ("same weight", "same-weight"), ("same thing", "same-again"),
        ("rest pause", "rest-pause"), ("drop set", "drop-set"), ("warm up", "warm-up"),
        ("pull ups", "pull-ups"), ("pull up", "pull-up"), ("chin ups", "pull-ups"),
        ("scrap that", "scrap-that"), ("take that back", "scrap-that"),
        ("delete the last set", "delete-last-set"), ("delete last set", "delete-last-set"),
        ("rest timer", "rest-timer"), ("last time", "last-time"), ("last session", "last-time"),
        ("my pr", "my-pr"), ("personal record", "my-pr"),
        ("nothing left", "nothing-left"), ("all out", "all-out"), ("each arm", "per-side")
    ]

    /// Lowercase, strip punctuation (kept: `. , - / × x`), collapse whitespace,
    /// map Unicode fractions, and join known multi-word phrases.
    public static func normalize(_ text: String) -> String {
        var lowered = text.lowercased()
        lowered = lowered.replacingOccurrences(of: "½", with: " and a half")
        lowered = lowered.replacingOccurrences(of: "¼", with: " and a quarter")
        lowered = lowered.replacingOccurrences(of: "×", with: "x")
        let allowed = CharacterSet(charactersIn: ".,-/x ").union(.alphanumerics)
        let stripped = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        var joined = String(stripped)
        for (phrase, token) in phraseJoins {
            joined = joined.replacingOccurrences(of: phrase, with: token)
        }
        let components = joined.split(separator: " ").map(String.init)
        return components.joined(separator: " ")
    }

    /// Splits normalised text into raw words (phrases already joined).
    public static func words(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Full pipeline: normalise, fold number-word runs, tag units/keywords.
    public static func tokenize(_ text: String) -> [Token] {
        let raw = words(text)
        var tokens: [Token] = []
        var idx = 0
        while idx < raw.count {
            let word = raw[idx]
            if let (value, consumed) = NumberWords.parse(raw, at: idx), consumed > 0 {
                tokens.append(.number(value))
                idx += consumed
                continue
            }
            if let unit = unitKind(for: word) {
                tokens.append(.unit(unit))
                idx += 1
                continue
            }
            if keywords.contains(word) {
                tokens.append(.keyword(word))
                idx += 1
                continue
            }
            tokens.append(.word(word))
            idx += 1
        }
        return tokens
    }

    /// Maps a bare word to the unit it names, if any.
    static func unitKind(for word: String) -> UnitKind? {
        switch word {
        case "kg", "kilo", "kilos", "kilogram", "kilograms": return .kg
        case "lb", "lbs", "pound", "pounds": return .lb
        case "plate", "plates": return .plates
        case "second", "seconds", "secs", "sec": return .seconds
        case "minute", "minutes", "min", "mins": return .minutes
        default: return nil
        }
    }
}
