import Foundation

/// Collapses English number words (and speech-recogniser digit strings) into
/// `Double` values: "one hundred and two and a half" → 102.5.
public enum NumberWords {
    private static let units: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    /// "ninety-five" → ["ninety", "five"]; `nil` unless every part is a number word.
    static func hyphenatedNumberWords(_ word: String) -> [String]? {
        guard word.contains("-") else { return nil }
        let parts = word.split(separator: "-").map(String.init)
        guard parts.count > 1, parts.allSatisfy(isBareNumberWord) else { return nil }
        return parts
    }

    /// Parses the longest number phrase starting at `words[index]`.
    /// Returns the value and how many words it consumed, or `nil` if
    /// `words[index]` doesn't start a number.
    public static func parse(_ words: [String], at index: Int) -> (value: Double, consumed: Int)? {
        guard index < words.count else { return nil }
        if let literal = literalDigits(words[index]) { return (literal, 1) }
        if let digitTens = compoundDigitTens(words, index) { return digitTens }
        if let digits = digitString(words, index) { return digits }
        return wordNumber(words, index)
    }

    /// Parses exactly one word as a number, with no compounding.
    public static func parseSingleWord(_ word: String) -> Double? {
        if let literal = literalDigits(word) { return literal }
        if let unitValue = units[word] { return Double(unitValue) }
        if let tensValue = tens[word] { return Double(tensValue) }
        if word == "hundred" { return 100 }
        return nil
    }

    /// Parses a number phrase but gives back its last 1–9 units word when
    /// "reps" follows: "twenty five eight reps" → 25 (2 words), "twenty eight
    /// reps" → 20 (1 word), "twenty five reps" → 20 (1 word).
    public static func parseBeforeReps(_ words: [String], at index: Int) -> (value: Double, consumed: Int)? {
        guard let (value, consumed) = parse(words, at: index) else { return nil }
        let last = index + consumed - 1
        guard consumed > 1, repsFollows(words, at: index + consumed), unitsWord(words, at: last) != nil,
              let shorter = parse(Array(words[index..<last]), at: 0), shorter.consumed == consumed - 1
        else { return (value, consumed) }
        return (shorter.value, consumed - 1)
    }

    /// True when `words[index]` is "reps"/"rep": the number before it is a rep count,
    /// so a compound must not swallow it ("minus twenty eight reps" → 20, then 8 reps).
    static func repsFollows(_ words: [String], at index: Int) -> Bool {
        index < words.count && (words[index] == "reps" || words[index] == "rep")
    }

    /// "and a half" / "and a quarter" starting at `words[index]`: the fraction and words consumed.
    public static func andAFraction(_ words: [String], at index: Int) -> (fraction: Double, consumed: Int)? {
        guard index + 2 < words.count, words[index] == "and",
              words[index + 1] == "a" || words[index + 1] == "an" else { return nil }
        if words[index + 2] == "half" { return (0.5, 3) }
        if words[index + 2] == "quarter" { return (0.25, 3) }
        return nil
    }

    /// The largest literal the recogniser may hand us. Nothing spoken in a gym is a million of
    /// anything; beyond it a mis-heard digit string ("99999999999999999999") used to flow into
    /// `Int(Double)` downstream, which traps above 9.2e18.
    static let maxLiteral = 1_000_000.0

    private static func literalDigits(_ word: String) -> Double? {
        guard let value = Double(word), word.rangeOfCharacter(from: .letters) == nil else { return nil }
        guard value.isFinite, value.magnitude <= maxLiteral else { return nil }
        return value
    }

    private static func unitsWord(_ words: [String], at index: Int) -> Int? {
        guard index < words.count, let value = units[words[index]], value >= 1, value <= 9 else { return nil }
        return value
    }

    /// "one twenty" → 120, "two twenty five" → 225: a lone unit digit immediately
    /// followed by a tens/teen word is read as a hundred-group, not added. The
    /// units word after the tens is absorbed unless "reps" follows it — "one
    /// twenty eight reps" is 120 for 8.
    private static func compoundDigitTens(_ words: [String], _ index: Int) -> (Double, Int)? {
        guard let digit = units[words[index]], digit >= 1, digit <= 9, index + 1 < words.count
        else { return nil }
        let next = words[index + 1]
        if let tensValue = tens[next] {
            var value = digit * 100 + tensValue
            var consumed = 2
            if let unitsValue = unitsWord(words, at: index + 2), !repsFollows(words, at: index + 3) {
                value += unitsValue
                consumed = 3
            }
            return (Double(value), consumed)
        }
        if let teenValue = units[next], teenValue >= 10 { return (Double(digit * 100 + teenValue), 2) }
        return nil
    }

    /// "one oh two point five" → 102.5: digits spoken one at a time, optionally
    /// followed by "point" and more single digits.
    private static func digitString(_ words: [String], _ index: Int) -> (Double, Int)? {
        var cursor = index
        var digits = ""
        while cursor < words.count, let digit = units[words[cursor]], digit <= 9,
              isLoneDigitContext(words, cursor) {
            digits += String(digit)
            cursor += 1
        }
        guard digits.count >= 2 else { return nil }
        var value = Double(digits) ?? 0
        var consumed = cursor - index
        if cursor < words.count, words[cursor] == "point",
           let (fraction, used) = decimalTail(words, cursor + 1) {
            value += fraction
            consumed += 1 + used
        }
        return (value, consumed)
    }

    /// A digit only counts as part of a digit-string when a neighbour is a bare
    /// single digit too (so "eight" alone isn't swallowed as digit-string mode).
    private static func isLoneDigitContext(_ words: [String], _ index: Int) -> Bool {
        func loneDigit(_ word: String) -> Bool {
            guard let value = units[word] else { return false }
            return value <= 9
        }
        let prevIsDigit = index > 0 && loneDigit(words[index - 1])
        let nextIsDigit = index + 1 < words.count && loneDigit(words[index + 1])
        return prevIsDigit || nextIsDigit
    }

    private static func decimalTail(_ words: [String], _ start: Int) -> (Double, Int)? {
        var cursor = start
        var digits = ""
        while cursor < words.count, let digit = units[words[cursor]], digit <= 9 {
            digits += String(digit)
            cursor += 1
        }
        guard !digits.isEmpty, let fraction = Double("0.\(digits)") else { return nil }
        return (fraction, cursor - start)
    }

    /// General compound word-number: "a hundred", "hundred and two and a half",
    /// "three", "eight and a half".
    private static func wordNumber(_ words: [String], _ index: Int) -> (Double, Int)? {
        if let prefixed = aOrAnPrefixed(words, index) { return prefixed }
        var cursor = index
        var total = 0.0
        var current = 0.0
        var sawAny = false
        while cursor < words.count {
            guard let step = consumeNumberWord(words, cursor, current: &current, total: &total) else { break }
            cursor = step
            sawAny = true
            if let (fraction, consumed) = pointSuffix(words, cursor) {
                return (total + current + fraction, consumed - index)
            }
        }
        total += current
        guard sawAny else { return nil }
        if let (bonus, consumed) = andAFraction(words, at: cursor) {
            return (total + bonus, cursor + consumed - index)
        }
        return (total, cursor - index)
    }

    /// "a hundred" / "a quarter" / "a half" as the very first word.
    private static func aOrAnPrefixed(_ words: [String], _ index: Int) -> (Double, Int)? {
        guard words[index] == "a" || words[index] == "an", index + 1 < words.count else { return nil }
        switch words[index + 1] {
        case "hundred": return wordNumber(words, index + 1).map { ($0.0, $0.1 + 1) }
        case "quarter": return (0.25, 2)
        case "half": return (0.5, 2)
        default: return nil
        }
    }

    /// Consumes one step of the loop (a scale word, a tens[+units] pair, a unit,
    /// or an "and" joiner) and returns the next cursor, or `nil` to stop.
    private static func consumeNumberWord(
        _ words: [String], _ cursor: Int, current: inout Double, total: inout Double
    ) -> Int? {
        let word = words[cursor]
        if word == "hundred" || word == "thousand" {
            let scale = word == "hundred" ? 100.0 : 1000.0
            current = (current == 0 ? 1 : current) * scale
            total += current
            current = 0
            return cursor + 1
        }
        // A tens word may be followed by exactly one 1–9 units word ("twenty five"),
        // never by a teen ("ninety twelve" is two separate numbers, not 102).
        if current == 0, let tensValue = tens[word] {
            current = Double(tensValue)
            var next = cursor + 1
            if let nextUnit = unitsWord(words, at: next) {
                current += Double(nextUnit)
                next += 1
            }
            return next
        }
        if current == 0, let unitValue = units[word], unitValue != 0 {
            current = Double(unitValue)
            return cursor + 1
        }
        if word == "and", cursor + 1 < words.count, isBareNumberWord(words[cursor + 1]) {
            return cursor + 1
        }
        return nil
    }

    private static func pointSuffix(_ words: [String], _ cursor: Int) -> (Double, Int)? {
        guard cursor < words.count, words[cursor] == "point",
              let (fraction, used) = decimalTail(words, cursor + 1) else { return nil }
        return (fraction, cursor + 1 + used)
    }

    private static func isBareNumberWord(_ word: String) -> Bool {
        units[word] != nil || tens[word] != nil || word == "hundred" || word == "thousand"
    }
}
