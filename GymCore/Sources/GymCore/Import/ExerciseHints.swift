import Foundation

/// Best-effort hints for an exercise a third-party import couldn't match against the library
/// (`WorkoutImportService.resolveExercise`) — so the invented custom it creates still has a
/// muscle map and a sensible logging style instead of `primary: []`/`.weightReps` for everything.
/// Never authoritative for a matched library exercise, only a starting point the user can correct.
public enum ExerciseHints {
    /// A custom exercise's `loggingStyle` — mirrors the app's own set of styles (see
    /// `ExerciseModel.loggingStyle`); this is the canonical GymCore-side vocabulary another layer
    /// maps its own type onto by `rawValue`.
    public enum LoggingStyle: String, CaseIterable, Codable, Sendable {
        case weightReps, bodyweightReps, assisted, weightedBodyweight, timedHold, cardio
    }

    /// Derives primary muscles for an invented exercise: a FitNotes `category` column first, then
    /// keywords in the exercise's own name. Empty when neither says anything — the user assigns
    /// muscles by hand.
    public static func primaryMuscles(name: String, category: String?) -> [Muscle] {
        if let category, let muscles = muscles(forCategory: category) {
            return muscles
        }
        return muscles(forName: name)
    }

    /// Derives a logging style from what the imported sets for this exercise actually carried:
    /// distance (with or without time) and no reps is cardio; time alone and no reps is a timed
    /// hold; anything with reps — or nothing measured at all — is ordinary weight × reps.
    public static func loggingStyle(hasReps: Bool, hasTime: Bool, hasDistance: Bool) -> LoggingStyle {
        if !hasReps, hasDistance { return .cardio }
        if !hasReps, hasTime { return .timedHold }
        return .weightReps
    }

    private static let categoryMuscles: [String: [Muscle]] = [
        "chest": [.chest], "back": [.lats], "legs": [.quads], "shoulders": [.delts],
        "biceps": [.biceps], "triceps": [.triceps], "abs": [.abs], "calves": [.calves],
        "forearms": [.forearms], "glutes": [.glutes], "hamstrings": [.hams]
    ]

    private static func muscles(forCategory category: String) -> [Muscle]? {
        categoryMuscles[category.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Keyword → muscle rules, checked in order (first match wins). Multi-word entries are matched
    /// as a substring of the name with punctuation collapsed to spaces; single words are matched
    /// against whole name-words, allowing a short suffix (plural "curls", "squats") but not an
    /// unrelated longer word that merely starts the same ("lateral" must not trip "lat").
    private static let nameRules: [(keywords: [String], muscles: [Muscle])] = [
        (["curl"], [.biceps]),
        (["pushdown", "skull"], [.triceps]),
        (["bench", "fly", "chest"], [.chest]),
        (["row", "pulldown", "pull-up", "lat"], [.lats]),
        (["deadlift"], [.lowerBack, .hams]),
        (["squat", "leg press", "lunge"], [.quads]),
        (["calf"], [.calves]),
        (["lateral raise", "overhead", "shoulder"], [.delts]),
        (["shrug"], [.traps]),
        (["crunch", "plank", "ab"], [.abs]),
        (["hip thrust", "glute"], [.glutes])
    ]

    private static func muscles(forName name: String) -> [Muscle] {
        let words = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let compact = words.joined()
        let spaced = words.joined(separator: " ")
        for rule in nameRules {
            let matched = rule.keywords.contains {
                matches($0, words: words, compact: compact, spaced: spaced)
            }
            if matched { return rule.muscles }
        }
        return []
    }

    private static func matches(_ keyword: String, words: [String], compact: String, spaced: String) -> Bool {
        if keyword.contains(" ") {
            return spaced.contains(keyword)
        }
        let normalized = keyword.replacingOccurrences(of: "-", with: "")
        if keyword.contains("-"), compact.contains(normalized) {
            return true
        }
        return words.contains { word in
            word.hasPrefix(normalized) && word.count - normalized.count <= 2
        }
    }
}
