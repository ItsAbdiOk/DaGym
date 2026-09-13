import Foundation

/// Collapses English number words (and speech-recogniser digit strings) into
/// `Double` values. Used by `Tokenizer` to fold a run of words like
/// "one hundred and two and a half" into a single numeric token.
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

    /// True for any word that can take part in a number phrase.
    public static func isNumberWord(_ word: String) -> Bool {
        units[word] != nil || tens[word] != nil || word == "hundred" || word == "thousand"
            || word == "a" || word == "an" || word == "point" || word == "half" || word == "quarter"
            || word == "and" || Double(word) != nil
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

    /// Parses exactly one word as a number, with no compounding — used where a
    /// trailing word could otherwise be swallowed into a bigger number
    /// (e.g. "minus twenty eight reps": the assistance is 20, not 28).
    public static func parseSingleWord(_ word: String) -> Double? {
        if let literal = literalDigits(word) { return literal }
        if let unitValue = units[word] { return Double(unitValue) }
        if let tensValue = tens[word] { return Double(tensValue) }
        if word == "hundred" { return 100 }
        return nil
    }

    private static func literalDigits(_ word: String) -> Double? {
        guard let value = Double(word), word.rangeOfCharacter(from: .letters) == nil else { return nil }
        return value
    }

    /// "one twenty" → 120: a lone unit digit immediately followed by a tens/teen word
    /// is read as a hundred-group, not added.
    private static func compoundDigitTens(_ words: [String], _ index: Int) -> (Double, Int)? {
        guard let digit = units[words[index]], digit >= 1, digit <= 9, index + 1 < words.count
        else { return nil }
        let next = words[index + 1]
        if let tensValue = tens[next] { return (Double(digit * 100 + tensValue), 2) }
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
        if let (bonus, consumed) = andAFractionSuffix(words, cursor) {
            return (total + bonus, consumed - index)
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
            if next < words.count, let nextUnit = units[words[next]], nextUnit >= 1, nextUnit <= 9 {
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

    private static func andAFractionSuffix(_ words: [String], _ cursor: Int) -> (Double, Int)? {
        guard cursor + 2 < words.count, words[cursor] == "and",
              words[cursor + 1] == "a" || words[cursor + 1] == "an" else { return nil }
        if words[cursor + 2] == "half" { return (0.5, cursor + 3) }
        if words[cursor + 2] == "quarter" { return (0.25, cursor + 3) }
        return nil
    }

    private static func isBareNumberWord(_ word: String) -> Bool {
        units[word] != nil || tens[word] != nil || word == "hundred" || word == "thousand"
    }
}
