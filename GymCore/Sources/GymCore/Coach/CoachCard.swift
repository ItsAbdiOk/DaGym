import Foundation

/// How urgently a card deserves the lifter's attention. Ordered low to high so
/// `CoachCard.priority` can sort the most pressing cards first.
public enum CoachSeverity: Int, Comparable, Hashable, Sendable {
    case info, notice, warning

    public static func < (lhs: CoachSeverity, rhs: CoachSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One piece of structured evidence behind a card — a number or date the rule actually fired on,
/// not prose. The app layer formats these for display (and in the unit the lifter has chosen).
public enum CoachEvidenceValue: Hashable, Sendable {
    case count(Int)
    case weightKg(Double)
    case date(Date)
    /// Any other numeric reading — a ratio, a percent, a fractional set count.
    case number(Double)
    case text(String)
}

/// A labelled piece of evidence, e.g. `("Consecutive misses", .count(3))`.
public struct CoachEvidenceItem: Hashable, Sendable {
    public var label: String
    public var value: CoachEvidenceValue

    public init(_ label: String, _ value: CoachEvidenceValue) {
        self.label = label
        self.value = value
    }
}

/// A suggested next step, described as data so the app layer decides how to present and apply it
/// (a button label, a sheet, a routine edit) rather than the engine baking in copy or UI.
public enum CoachSuggestedAction: Hashable, Sendable {
    /// Deload `exerciseName` to `toWeightKg` for `sets` sets.
    case deloadExercise(exerciseName: String, toWeightKg: Double, sets: Int)
    /// Swap `exerciseName` for `candidateName` (`candidateID` identifies it in the library).
    case substituteExercise(exerciseName: String, candidateID: UUID, candidateName: String)
    /// Add a session on `weekday`.
    case addSession(weekday: Weekday)
    /// Take a rest day, or go easy on `muscle` specifically.
    case restMuscle(Muscle)
    /// Ease back in at `loadFraction` of the last known working weight.
    case easeBackIn(loadFraction: Double)
    /// No concrete action — the card is informational only (e.g. a PR callout).
    case none
}

/// A card the coach surfaces for the lifter to approve or dismiss (plan.md: "ten hand-written
/// rules that look at training history and produce cards the user can Approve or Dismiss").
/// `Sendable`, `Comparable` (by `priority`, most important last so `.sorted(by: >).prefix(n)`
/// reads naturally as "top N"), and carries its own stable `fingerprint` for dismissal/cooldown.
public struct CoachCard: Hashable, Sendable {
    public var rule: CoachRule
    public var severity: CoachSeverity
    public var title: String
    public var body: String
    public var evidence: [CoachEvidenceItem]
    public var suggestedAction: CoachSuggestedAction
    /// Stable across launches: identifies *this* evidence, not just the rule, so dismissing a
    /// stalled-bench-press card doesn't silence a later stalled-squat card, and fresh evidence
    /// (a new week, a new lift) isn't suppressed by an old dismissal.
    public var fingerprint: String
    /// When the engine produced this card (`now`, from the `CoachEngine.cards` call).
    public var firedDate: Date

    public init(
        rule: CoachRule, severity: CoachSeverity, title: String, body: String,
        evidence: [CoachEvidenceItem], suggestedAction: CoachSuggestedAction = .none,
        distinguishingKey: String = "", firedDate: Date
    ) {
        self.rule = rule
        self.severity = severity
        self.title = title
        self.body = body
        self.evidence = evidence
        self.suggestedAction = suggestedAction
        self.fingerprint = Self.makeFingerprint(rule: rule, key: distinguishingKey)
        self.firedDate = firedDate
    }

    /// A deterministic 64-bit FNV-1a hash rendered as hex — stable across launches, unlike
    /// `hashValue`, so it can be persisted and compared to a stored dismissal fingerprint. Mirrors
    /// `DeloadSuggestion.fingerprint`'s approach in `DeloadDetector.swift`.
    static func makeFingerprint(rule: CoachRule, key: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (rule.rawValue + "|" + key).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

extension CoachCard: Comparable {
    /// Orders ascending by priority: severity first, then more recently-fired cards outrank
    /// older ones of the same severity, with the rule id as a final deterministic tiebreak so two
    /// cards are never "equally" ordered by chance. Callers wanting the top N sort descending.
    public static func < (lhs: CoachCard, rhs: CoachCard) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
        if lhs.firedDate != rhs.firedDate { return lhs.firedDate < rhs.firedDate }
        return lhs.rule.rawValue > rhs.rule.rawValue
    }
}
