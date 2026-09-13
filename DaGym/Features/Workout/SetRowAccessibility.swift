import GymCore

/// Pure label-building for `SetRow`'s VoiceOver strings — kept free of SwiftUI so it's
/// cheap to unit test. Formatting (weight/reps text, unit symbol) is the caller's job;
/// this only assembles the words.
enum SetRowAccessibility {
    /// The done-toggle button's label: what set this is, its weight and reps, and
    /// whether it's logged. `weight` and `reps` are already display-formatted
    /// (e.g. "82.5" and "8" or "AMRAP") so this stays unit-agnostic.
    static func label(kind: SetKind, weight: String, reps: String, unit: String, done: Bool) -> String {
        let doneWord = done ? "done" : "not done"
        return "\(kindPhrase(kind)), \(weight) \(unit) by \(reps) reps, \(doneWord)"
    }

    /// A noun phrase for `kind`, avoiding "Drop set set" for kinds whose `displayName`
    /// already ends in "set".
    private static func kindPhrase(_ kind: SetKind) -> String {
        switch kind {
        case .working: "Set"
        case .drop: kind.displayName
        default: "\(kind.displayName) set"
        }
    }
}
