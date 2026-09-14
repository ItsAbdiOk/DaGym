import Foundation

/// A library entry usable in a mid-workout substitution search — either the
/// exercise being swapped out or a candidate replacement. Mirrors the
/// substitution-relevant fields of `DaGym.ExerciseInfo` without this module
/// depending on the app target.
public struct SubstitutionCandidate: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var primary: [Muscle]
    public var secondary: [Muscle]
    /// "barbell", "dumbbell", "machine", "cable", "bodyweight", …
    public var equipment: String
    /// "compound" or "isolation".
    public var mechanic: String
    public var loggingStyle: String

    public init(
        id: UUID, name: String, primary: [Muscle], secondary: [Muscle] = [],
        equipment: String, mechanic: String, loggingStyle: String = "weightReps"
    ) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
        self.equipment = equipment
        self.mechanic = mechanic
        self.loggingStyle = loggingStyle
    }
}

/// Why the user is asking for a swap. Drives both which candidates are
/// filtered out and how the survivors are scored.
public enum SwapReason: Hashable, Sendable {
    case machineTaken
    case noBarbell
    case painArea(Muscle)
    case shoulderHurts
    case shortOnTime
    /// The lifter keeps missing or failing this exercise (CoachEngine's struggling-lift rule) —
    /// no equipment exclusion or pain steer, just the same-muscle/mechanic scoring.
    case strugglingWithExercise

    /// The equipment kind this reason rules out entirely, when it names one.
    var excludedEquipment: String? {
        switch self {
        case .machineTaken: "machine"
        case .noBarbell: "barbell"
        case .painArea, .shoulderHurts, .shortOnTime, .strugglingWithExercise: nil
        }
    }

    /// The muscle to steer away from, for the two pain-related reasons.
    /// `.shoulderHurts` is shorthand for `.painArea(.delts)`.
    var painMuscle: Muscle? {
        switch self {
        case .painArea(let muscle): muscle
        case .shoulderHurts: .delts
        case .machineTaken, .noBarbell, .shortOnTime, .strugglingWithExercise: nil
        }
    }
}

/// One scored replacement, ready for `SwapExerciseSheet`.
public struct ScoredSubstitute: Identifiable, Hashable, Sendable {
    public var candidate: SubstitutionCandidate
    public var score: Double
    /// One line explaining the pick, e.g. "Same muscles, dumbbells only".
    public var reason: String
    public var id: UUID { candidate.id }
}

/// Rule-based mid-workout exercise substitution (plan §6.6). No ML, no
/// network — just the same-muscle / available-equipment / fatigue rules a
/// trainer would apply on the spot.
public enum Substitutions {
    /// A `recoveryMap` value above this counts as "spent enough to steer away from" a candidate —
    /// our own weight, tuned separately from `TrainingConstants.recoveryHeadlineThreshold` (which
    /// governs when a muscle is named in the recovery headline, not ranked here).
    private static let fatigueThreshold = 0.6
    /// Baseline score every eligible candidate starts from — our own weight, high enough that the
    /// adjustments below can't push a candidate negative on their own.
    private static let baseScore = 10.0
    /// Score bonus per shared primary muscle — our own weight.
    private static let sharedPrimaryMuscleWeight = 3.0
    /// Score bonus per shared secondary muscle — our own weight, half the primary weight.
    private static let sharedSecondaryMuscleWeight = 1.5
    /// Score bonus when the candidate shares the same mechanic (compound/isolation) — our own weight.
    private static let mechanicMatchBonus = 1.0
    /// `.shortOnTime`: bonus for a compound candidate, penalty for an isolation one — our own weights.
    private static let shortOnTimeCompoundBonus = 4.0
    private static let shortOnTimeIsolationPenalty = -1.0
    /// Pain-related reasons: penalty when the candidate still loads the sore muscle, bonus when it's
    /// isolation/machine (so it can be worked around it) — our own weights.
    private static let painMusclePenalty = -6.0
    private static let painAvoidanceBonus = 2.0
    /// Fatigue penalty per point of "spent" past `fatigueThreshold` — our own weight.
    private static let fatiguePenaltyScale = 10.0

    /// Up to 3 candidates for `exercise`, best first. Empty when nothing in `library` shares a
    /// primary muscle and available equipment with `exercise`, once `reason`'s equipment
    /// exclusion (if any) is applied.
    public static func candidates(
        for exercise: SubstitutionCandidate,
        reason: SwapReason,
        library: [SubstitutionCandidate],
        available equipment: Set<String>,
        recoveryMap: [Muscle: Double]
    ) -> [ScoredSubstitute] {
        let primaryMuscles = Set(exercise.primary)
        let eligible = library.filter { candidate in
            candidate.id != exercise.id
                && !Set(candidate.primary).isDisjoint(with: primaryMuscles)
                && equipment.contains(candidate.equipment)
                && candidate.equipment != reason.excludedEquipment
        }

        let scored = eligible.map { candidate in
            ScoredSubstitute(
                candidate: candidate,
                score: score(candidate, exercise: exercise, reason: reason, recoveryMap: recoveryMap),
                reason: why(candidate, exercise: exercise, reason: reason)
            )
        }

        let ranked = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.candidate.name < rhs.candidate.name
        }
        return Array(ranked.prefix(3))
    }

    private static func score(
        _ candidate: SubstitutionCandidate, exercise: SubstitutionCandidate, reason: SwapReason,
        recoveryMap: [Muscle: Double]
    ) -> Double {
        var score = baseScore
        score += Double(Set(candidate.primary).intersection(exercise.primary).count)
            * sharedPrimaryMuscleWeight
        score += Double(Set(candidate.secondary).intersection(exercise.secondary).count)
            * sharedSecondaryMuscleWeight
        if candidate.mechanic == exercise.mechanic { score += mechanicMatchBonus }
        score += reasonAdjustment(candidate, reason: reason)
        score += fatiguePenalty(candidate, recoveryMap: recoveryMap)
        return score
    }

    /// `.shortOnTime` favors compound lifts; the two pain-related reasons penalise candidates
    /// that still load the sore muscle and favor isolation/machine variants that don't.
    /// `.machineTaken`/`.noBarbell` are already fully handled by the equipment filter above.
    private static func reasonAdjustment(_ candidate: SubstitutionCandidate, reason: SwapReason) -> Double {
        switch reason {
        case .shortOnTime:
            return candidate.mechanic == "compound" ? shortOnTimeCompoundBonus : shortOnTimeIsolationPenalty
        case .painArea, .shoulderHurts:
            var adjustment = 0.0
            if let muscle = reason.painMuscle, touches(candidate, muscle) { adjustment += painMusclePenalty }
            if candidate.mechanic == "isolation" || candidate.equipment == "machine" {
                adjustment += painAvoidanceBonus
            }
            return adjustment
        case .machineTaken, .noBarbell, .strugglingWithExercise:
            return 0
        }
    }

    /// A muscle already fatigued past `fatigueThreshold` makes a candidate that hits it a worse
    /// pick — the more spent it is, the bigger the penalty.
    private static func fatiguePenalty(
        _ candidate: SubstitutionCandidate, recoveryMap: [Muscle: Double]
    ) -> Double {
        (candidate.primary + candidate.secondary).reduce(0) { total, muscle in
            guard let spent = recoveryMap[muscle], spent > fatigueThreshold else { return total }
            return total - (spent - fatigueThreshold) * fatiguePenaltyScale
        }
    }

    private static func touches(_ candidate: SubstitutionCandidate, _ muscle: Muscle) -> Bool {
        candidate.primary.contains(muscle) || candidate.secondary.contains(muscle)
    }

    private static func why(
        _ candidate: SubstitutionCandidate, exercise: SubstitutionCandidate, reason: SwapReason
    ) -> String {
        let shared = Set(candidate.primary).intersection(exercise.primary)
        // `shared` is a Set, whose iteration order isn't stable across launches — pick
        // deterministically by walking the exercise's own (ordered) primary muscles instead of
        // reading `.first` off the set.
        let muscleName = exercise.primary.first { shared.contains($0) }?.displayName.lowercased() ?? "muscles"
        switch reason {
        case .painArea, .shoulderHurts:
            let area = reason.painMuscle?.displayName.lowercased() ?? "sore spot"
            return "Same \(muscleName), eases the \(area)"
        case .shortOnTime:
            return "Same \(muscleName), stays compound"
        case .machineTaken, .noBarbell:
            return "Same \(muscleName), \(candidate.equipment) only"
        case .strugglingWithExercise:
            return "Same \(muscleName), a change of stimulus"
        }
    }
}
