import GymCore

/// Pure label-building for `SetRow`'s VoiceOver strings — kept free of SwiftUI so it's
/// cheap to unit test. Formatting (weight/reps text, unit symbol) is the caller's job;
/// this only assembles the words.
enum SetRowAccessibility {
    /// The done-toggle button's label: what set this is, its weight and reps, and
    /// whether it's logged. `weight` and `reps` are already display-formatted
    /// (e.g. "82.5" and "8" or "AMRAP") so this stays unit-agnostic.
    static func label(
        kind: SetKind, weight: String, reps: String, unit: String, done: Bool, isCurrent: Bool = false
    ) -> String {
        let doneWord = done ? "done" : "not done"
        let current = isCurrent ? ", current set" : ""
        return "\(kindPhrase(kind)), \(weight) \(unit) by \(reps) reps, \(doneWord)\(current)"
    }

    /// The cardio row's done button: kind, the logged (or target) numbers, state, on-deck flag.
    static func cardioLabel(kind: SetKind, summary: String, done: Bool, isCurrent: Bool) -> String {
        let doneWord = done ? "done" : "not done"
        let current = isCurrent ? ", current set" : ""
        return "\(kindPhrase(kind)), \(summary), \(doneWord)\(current)"
    }

    /// The "previous" ghost column: "Previous, 80 kg by 8" or "No previous set".
    static func previousLabel(weight: String?, reps: Int?, unit: String) -> String {
        guard let weight, let reps else { return "No previous set" }
        return "Previous, \(weight) \(unit) by \(reps)"
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
