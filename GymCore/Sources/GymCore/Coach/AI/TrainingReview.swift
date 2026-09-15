import Foundation

/// One lift's four-week picture, pre-summarised by the app layer.
public struct LiftDigest: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// e1RM change over the window as a fraction (+0.04 = 4 % stronger). Nil with < 2 sessions.
    public var e1rmChangeFraction: Double?
    public var sessions: Int
    public var isStalled: Bool
    /// The plan's current rep target on this lift (low…high), when it has one.
    public var repLow: Int?
    public var repHigh: Int?
    /// The step a progression rule proposed for this lift should climb by — the lift's own
    /// increment on the lifter's grid (5 kg on a squat, 1 kg on a cable, 5 lb for a lb lifter),
    /// so a "put Squat on linear" card doesn't hard-code 2.5 kg.
    public var incrementKg: Double

    public init(
        id: UUID, name: String, e1rmChangeFraction: Double? = nil, sessions: Int, isStalled: Bool = false,
        repLow: Int? = nil, repHigh: Int? = nil,
        incrementKg: Double = TrainingConstants.defaultUpperBodyIncrementKg
    ) {
        self.id = id
        self.name = name
        self.e1rmChangeFraction = e1rmChangeFraction
        self.sessions = sessions
        self.isStalled = isStalled
        self.repLow = repLow
        self.repHigh = repHigh
        self.incrementKg = incrementKg
    }
}

/// The four-week digest the training review reads — per-lift trend, adherence, coverage gaps,
/// and the small closed pool of exercises a change may add or swap to. Every number here comes
/// from an existing GymCore engine (`OneRepMax`, `Adherence`, `BodySeries.setsPerMuscle`,
/// `StallState`); the model only ever sees the `facts` lines and the pool.
public struct TrainingDigest: Hashable, Sendable {
    public var weeks: Int
    public var lifts: [LiftDigest]
    public var adherencePercent: Int?
    public var coverageGaps: [Muscle]
    /// Weekdays with a planned session, for `moveRestDay`.
    public var trainingDays: [Weekday]
    /// Exercises a change may add or swap to — a handful per gap muscle, chosen by the app layer.
    public var pool: [SubstitutionCandidate]

    public init(
        weeks: Int, lifts: [LiftDigest], adherencePercent: Int? = nil, coverageGaps: [Muscle] = [],
        trainingDays: [Weekday] = [], pool: [SubstitutionCandidate] = []
    ) {
        self.weeks = weeks
        self.lifts = lifts
        self.adherencePercent = adherencePercent
        self.coverageGaps = coverageGaps
        self.trainingDays = trainingDays
        self.pool = pool
    }

    public enum FactID {
        public static let adherence = "adherence"
        public static func gap(_ muscle: Muscle) -> String { "gap.\(muscle.rawValue)" }
        public static func lift(_ index: Int) -> String { "lift\(index + 1)" }
    }

    public var facts: [CoachFact] {
        var facts: [CoachFact] = []
        if let adherencePercent {
            facts.append(CoachFact(
                id: FactID.adherence, text: "Adherence \(adherencePercent)% over \(weeks) weeks"
            ))
        }
        for muscle in coverageGaps {
            facts.append(CoachFact(
                id: FactID.gap(muscle), text: "\(muscle.displayName) under-trained in the window"
            ))
        }
        for (index, lift) in lifts.enumerated() {
            var text = "\(lift.name): \(lift.sessions) sessions"
            if let change = lift.e1rmChangeFraction {
                let percent = Int((change * 100).rounded())
                text += ", e1RM \(percent >= 0 ? "+" : "")\(percent)%"
            }
            if lift.isStalled { text += ", stalled" }
            if let low = lift.repLow, let high = lift.repHigh { text += ", \(low)–\(high) reps" }
            facts.append(CoachFact(id: FactID.lift(index), text: text))
        }
        return facts
    }

    public var factIDs: Set<String> { Set(facts.map(\.id)) }
    public var liftIDs: Set<UUID> { Set(lifts.map(\.id)) }
    public var poolIDs: Set<UUID> { Set(pool.map(\.id)) }
}

/// The closed set of changes a review may propose. Anything the model says that doesn't map
/// onto one of these is not a change — it's dropped.
public enum ReviewChange: Hashable, Sendable {
    case addExercise(UUID)
    case swapExercise(from: UUID, to: UUID)
    case changeRepRange(exerciseID: UUID, low: Int, high: Int)
    case changeProgressionRule(exerciseID: UUID, rule: ProgressionRule)
    case moveRestDay(from: Weekday, to: Weekday)
    case deloadLift(UUID)

    public static let repRange = 1...30
}

/// One proposed change plus the evidence it cites.
public struct ReviewProposal: Hashable, Sendable {
    public var change: ReviewChange
    public var claim: CoachClaim

    public init(change: ReviewChange, claim: CoachClaim) {
        self.change = change
        self.claim = claim
    }

    public static let maxProposals = 3
}

/// The gate between a review (model or rule) and the coach cards: at most three proposals, each
/// citing facts the digest actually contains, each naming only lifts in the programme and
/// exercises in the pool, rep ranges sane, no two proposals about the same change.
public enum TrainingReviewValidator {
    public static func validate(
        _ proposals: [ReviewProposal], digest: TrainingDigest
    ) -> [ReviewProposal] {
        let known = digest.factIDs
        // Pool names are fair game for a number ("add Cable Row 2"), and so is the change's own
        // value ("move to 8–12 reps") — everything else must be a value one of the facts states.
        let knownText = digest.facts.map(\.text) + digest.pool.map(\.name)
        var seen = Set<ReviewChange>()
        var result: [ReviewProposal] = []
        for proposal in proposals where proposal.claim.isGrounded(
            in: known, numbersFrom: knownText + [statedNumbers(in: proposal.change)]
        ) {
            guard isAllowed(proposal.change, digest: digest), !seen.contains(proposal.change) else {
                continue
            }
            seen.insert(proposal.change)
            result.append(proposal)
            if result.count == ReviewProposal.maxProposals { break }
        }
        return result
    }

    /// The numbers a change itself carries, as one line of text for the number check.
    static func statedNumbers(in change: ReviewChange) -> String {
        switch change {
        case .changeRepRange(_, let low, let high): "\(low) \(high)"
        case .changeProgressionRule(_, let rule): rule.explanation()
        case .addExercise, .swapExercise, .moveRestDay, .deloadLift: ""
        }
    }

    static func isAllowed(_ change: ReviewChange, digest: TrainingDigest) -> Bool {
        switch change {
        case .addExercise(let id):
            return digest.poolIDs.contains(id) && !digest.liftIDs.contains(id)
        case .swapExercise(let from, let to):
            return digest.liftIDs.contains(from) && digest.poolIDs.contains(to) && from != to
        case .changeRepRange(let id, let low, let high):
            return digest.liftIDs.contains(id) && ReviewChange.repRange.contains(low)
                && ReviewChange.repRange.contains(high) && low <= high
        case .changeProgressionRule(let id, let rule):
            return digest.liftIDs.contains(id) && hasPositiveStep(rule)
        case .moveRestDay(let from, let to):
            return from != to && digest.trainingDays.contains(from) && !digest.trainingDays.contains(to)
        case .deloadLift(let id):
            return digest.liftIDs.contains(id)
        }
    }

    /// A rule whose step is zero or negative would never progress — the same floor the app's
    /// `incrementRejectingNonPositive` applies, checked here so the model can't propose one.
    static func hasPositiveStep(_ rule: ProgressionRule) -> Bool {
        switch rule {
        case .linear(let incrementKg), .linearAMRAP(let incrementKg): incrementKg > 0
        case .doubleProgression(let low, let high, let incrementKg): incrementKg > 0 && low <= high
        case .assisted(let stepKg): stepKg > 0
        case .timed(let stepSeconds): stepSeconds > 0
        case .rpeBased, .percentOfTrainingMax, .bodyweight: true
        }
    }
}

/// The rule-based review: stalls become deloads, coverage gaps become additions from the pool,
/// low adherence with a crowded week becomes a moved rest day. Deterministic, and already valid.
public enum TrainingReviewRules {
    public static let lowAdherencePercent = 60

    public static func proposals(from digest: TrainingDigest) -> [ReviewProposal] {
        typealias Fact = TrainingDigest.FactID
        var proposals: [ReviewProposal] = []
        for (index, lift) in digest.lifts.enumerated() where lift.isStalled {
            let text = "\(lift.name) has stalled — back the load off and rebuild."
            proposals.append(ReviewProposal(
                change: .deloadLift(lift.id), claim: CoachClaim(text: text, citedFactIDs: [Fact.lift(index)])
            ))
        }
        for muscle in digest.coverageGaps {
            guard let pick = digest.pool.first(where: {
                $0.primary.contains(muscle) && !digest.liftIDs.contains($0.id)
            }) else { continue }
            let text = "\(muscle.displayName) is under-trained — add \(pick.name)."
            proposals.append(ReviewProposal(
                change: .addExercise(pick.id), claim: CoachClaim(text: text, citedFactIDs: [Fact.gap(muscle)])
            ))
        }
        return TrainingReviewValidator.validate(proposals, digest: digest)
    }
}
