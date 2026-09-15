import Foundation

/// The five questions the app can answer about a lifter's own training. The model reaches
/// these through tool calls; the rule fallback matches a typed question straight onto one.
/// Either way the numbers come from the store, never from the model.
public enum CoachToolQuery: Hashable, Sendable {
    case lastSessions(exercise: String)
    case weeklyVolume(muscle: String, weeks: Int)
    case personalRecords(exercise: String)
    case adherence(weeks: Int)
    case recovery(muscle: String)

    public static let defaultWeeks = 4
}

/// What a tool returned: one short paragraph of numbers the answer may repeat.
public struct CoachToolResult: Hashable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

/// Checks that an answer only contains numbers that some tool actually returned — the model
/// may phrase, it may not compute. Tokens are compared as values (82.5 matches "82.50"), so a
/// unit change or trailing zero doesn't fail an honest sentence.
public enum CoachAnswerValidator {
    /// Every numeric token in `text`, parsed. "3×8" yields 3 and 8; "12 Sep" yields 12.
    public static func numbers(in text: String) -> [Double] {
        var results: [Double] = []
        var current = ""
        for character in text {
            if character.isNumber || (character == "." && !current.isEmpty && !current.contains(".")) {
                current.append(character)
            } else {
                if let value = Double(current.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                    results.append(value)
                }
                current = ""
            }
        }
        if let value = Double(current.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            results.append(value)
        }
        return results
    }

    public static func isGrounded(answer: String, toolResults: [CoachToolResult]) -> Bool {
        let allowed = toolResults.flatMap { numbers(in: $0.text) }
        return numbers(in: answer).allSatisfy { number in
            allowed.contains { abs($0 - number) < 0.001 }
        }
    }
}

/// The rule-based "ask about your training": a keyword matcher from a typed question onto one
/// `CoachToolQuery`. Exercise and muscle names are matched against the lifter's own library so
/// "how's my bench" finds "Bench Press". Nil when no question shape matched.
public enum CoachQuestionMatcher {
    public static func query(for question: String, exerciseNames: [String]) -> CoachToolQuery? {
        let lowered = question.lowercased()
        let weeks = weeksMentioned(in: lowered) ?? CoachToolQuery.defaultWeeks
        let muscle = muscleMentioned(in: lowered)
        let exercise = exerciseMentioned(in: lowered, names: exerciseNames)

        if containsAny(lowered, ["pr", "record", "best", "max", "strongest"]), let exercise {
            return .personalRecords(exercise: exercise)
        }
        if containsAny(lowered, ["volume", "sets", "how much"]), let muscle {
            return .weeklyVolume(muscle: muscle, weeks: weeks)
        }
        if containsAny(lowered, ["recover", "fresh", "sore", "fatigue", "tired", "rest"]), let muscle {
            return .recovery(muscle: muscle)
        }
        let adherenceWords = [
            "adherence", "consistent", "consistency", "missed", "stick", "show up", "on track"
        ]
        if containsAny(lowered, adherenceWords) { return .adherence(weeks: weeks) }
        if let exercise { return .lastSessions(exercise: exercise) }
        if let muscle { return .weeklyVolume(muscle: muscle, weeks: weeks) }
        return nil
    }

    static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            // Whole-word match for short needles, so "pr" doesn't fire on "press" or "progress".
            needle.count <= 3
                ? text.split(whereSeparator: { !$0.isLetter }).contains { $0 == Substring(needle) }
                : text.contains(needle)
        }
    }

    private static let spelledNumbers = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "eight": 8, "twelve": 12
    ]

    static func weeksMentioned(in text: String) -> Int? {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for (index, word) in words.enumerated() where word.hasPrefix("week") && index > 0 {
            if let count = Int(words[index - 1]) { return min(max(count, 1), 52) }
            if let count = spelledNumbers[words[index - 1]] { return count }
        }
        if text.contains("this week") || text.contains("last week") { return 1 }
        return nil
    }

    /// The muscle's display name, matched by everyday words as well as the library's own.
    public static func muscleMentioned(in text: String) -> String? {
        let aliases: [(String, Muscle)] = [
            ("chest", .chest), ("pec", .chest), ("back", .lats), ("lat", .lats), ("shoulder", .delts),
            ("delt", .delts), ("quad", .quads), ("leg", .quads), ("hamstring", .hams), ("glute", .glutes),
            ("bicep", .biceps), ("tricep", .triceps), ("calf", .calves), ("calves", .calves), ("abs", .abs),
            ("core", .abs), ("trap", .traps), ("forearm", .forearms), ("lower back", .lowerBack),
            ("oblique", .obliques)
        ]
        return aliases.first { text.contains($0.0) }?.1.displayName
    }

    /// The longest library name whose every word appears in the question ("bench" matches
    /// "Bench Press" only via the first word, so a one-word question still resolves).
    public static func exerciseMentioned(in text: String, names: [String]) -> String? {
        let words = Set(text.split(whereSeparator: { !$0.isLetter }).map { String($0) })
        let scored = names.compactMap { name -> (String, Int)? in
            let parts = name.lowercased().split(separator: " ").map(String.init)
            let matched = parts.filter(words.contains).count
            guard matched > 0, matched == parts.count || parts.count <= 2 else { return nil }
            return (name, matched)
        }
        return scored.max { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.count > rhs.0.count
        }?.0
    }
}
