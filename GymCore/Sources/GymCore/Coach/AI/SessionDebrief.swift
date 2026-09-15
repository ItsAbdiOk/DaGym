import Foundation

/// Everything the workout debrief may talk about, already reduced to a handful of numbers by the
/// app layer (`WorkoutStore+CoachFacts.swift`). Each number becomes one `CoachFact` with a fixed
/// id, so the prompt is a dozen short lines and a claim can be checked against what it cites.
/// Nothing here comes from HealthKit — only sets the lifter logged in DaGym.
public struct SessionSummaryFacts: Hashable, Sendable {
    public var title: String
    public var durationMinutes: Int
    public var volumeKg: Double
    public var previousVolumeKg: Double?
    public var setsDone: Int
    public var previousSetsDone: Int?
    /// Planned sets left unticked.
    public var skippedSets: Int
    /// Completed sets that came up short of the same set last time, at the same or a heavier load.
    public var setsBelowLast: Int
    /// Exercise names that set a new headline PR this session.
    public var personalRecords: [String]
    public var averageRPE: Double?
    public var previousAverageRPE: Double?
    /// Exercises whose best e1RM moved up / down against the previous run of this routine.
    public var e1rmUp: [String]
    public var e1rmDown: [String]

    public init(
        title: String, durationMinutes: Int, volumeKg: Double, previousVolumeKg: Double? = nil,
        setsDone: Int, previousSetsDone: Int? = nil, skippedSets: Int = 0, setsBelowLast: Int = 0,
        personalRecords: [String] = [], averageRPE: Double? = nil, previousAverageRPE: Double? = nil,
        e1rmUp: [String] = [], e1rmDown: [String] = []
    ) {
        self.title = title
        self.durationMinutes = durationMinutes
        self.volumeKg = volumeKg
        self.previousVolumeKg = previousVolumeKg
        self.setsDone = setsDone
        self.previousSetsDone = previousSetsDone
        self.skippedSets = skippedSets
        self.setsBelowLast = setsBelowLast
        self.personalRecords = personalRecords
        self.averageRPE = averageRPE
        self.previousAverageRPE = previousAverageRPE
        self.e1rmUp = e1rmUp
        self.e1rmDown = e1rmDown
    }

    /// Fact ids, fixed so tests and the rule fallback can cite them by name.
    public enum FactID {
        public static let duration = "duration"
        public static let volume = "volume"
        public static let volumeChange = "volumeChange"
        public static let sets = "sets"
        public static let skipped = "skipped"
        public static let belowLast = "belowLast"
        public static let prs = "prs"
        public static let rpe = "rpe"
        public static let rpeDrift = "rpeDrift"
        public static let e1rmUp = "e1rmUp"
        public static let e1rmDown = "e1rmDown"
    }

    /// Volume change against the previous run, as a fraction (+0.05 = 5 % more). Nil without a
    /// previous run or when the previous volume was zero.
    public var volumeChangeFraction: Double? {
        guard let previousVolumeKg, previousVolumeKg > 0 else { return nil }
        return (volumeKg - previousVolumeKg) / previousVolumeKg
    }

    /// RPE now minus RPE last time, positive when this session felt harder.
    public var rpeDrift: Double? {
        guard let averageRPE, let previousAverageRPE else { return nil }
        return averageRPE - previousAverageRPE
    }

    /// The prompt's fact list. Only facts that exist are listed — a first run has no
    /// "volumeChange" line, so the model can't cite one. Weights are given in kg; the model is
    /// told not to repeat numbers, only to reason from them.
    public var facts: [CoachFact] {
        var facts: [CoachFact] = [
            CoachFact(id: FactID.duration, text: "Session lasted \(durationMinutes) min"),
            CoachFact(id: FactID.volume, text: "Total volume \(Int(volumeKg.rounded())) kg"),
            CoachFact(id: FactID.sets, text: "\(setsDone) working sets done")
        ]
        if let change = volumeChangeFraction {
            let percent = Int((change * 100).rounded())
            let text = "Volume \(Self.signed(percent))% vs last time"
            facts.append(CoachFact(id: FactID.volumeChange, text: text))
        }
        if skippedSets > 0 {
            facts.append(CoachFact(id: FactID.skipped, text: "\(skippedSets) planned sets skipped"))
        }
        if setsBelowLast > 0 {
            let text = "\(setsBelowLast) sets fell short of last time"
            facts.append(CoachFact(id: FactID.belowLast, text: text))
        }
        if !personalRecords.isEmpty {
            let names = personalRecords.joined(separator: ", ")
            facts.append(CoachFact(id: FactID.prs, text: "New PRs: \(names)"))
        }
        if let averageRPE {
            facts.append(CoachFact(id: FactID.rpe, text: "Average RPE \(Self.oneDecimal(averageRPE))"))
        }
        if let drift = rpeDrift {
            let sign = drift >= 0 ? "+" : ""
            let text = "RPE \(sign)\(Self.oneDecimal(drift)) vs last time"
            facts.append(CoachFact(id: FactID.rpeDrift, text: text))
        }
        if !e1rmUp.isEmpty {
            facts.append(CoachFact(id: FactID.e1rmUp, text: "e1RM up on \(e1rmUp.joined(separator: ", "))"))
        }
        if !e1rmDown.isEmpty {
            let text = "e1RM down on \(e1rmDown.joined(separator: ", "))"
            facts.append(CoachFact(id: FactID.e1rmDown, text: text))
        }
        return facts
    }

    public var factIDs: Set<String> { Set(facts.map(\.id)) }

    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func signed(_ value: Int) -> String { value >= 0 ? "+\(value)" : "\(value)" }
}

/// The debrief card's content: a 1…10 score and three short lists, every bullet citing the
/// facts it rests on. The model produces one of these (via the app layer's `@Generable` mirror)
/// and so does `DebriefRules` when no model is available — the card can't tell which.
public struct SessionDebrief: Hashable, Sendable {
    public var score: Int
    public var wentWell: [CoachClaim]
    public var watch: [CoachClaim]
    public var tryNext: [CoachClaim]

    public init(score: Int, wentWell: [CoachClaim], watch: [CoachClaim], tryNext: [CoachClaim]) {
        self.score = score
        self.wentWell = wentWell
        self.watch = watch
        self.tryNext = tryNext
    }

    public static let scoreRange = 1...10
    public static let maxBulletsPerList = 3
}

/// The strict gate every debrief passes through before the card shows it: the score must be in
/// range, and a bullet that cites nothing — or cites a fact id the input never contained, or
/// carries a number the facts never stated — is dropped rather than shown. Nil means "nothing
/// survived", and the card hides itself.
public enum DebriefValidator {
    public static func validate(_ debrief: SessionDebrief, facts: SessionSummaryFacts) -> SessionDebrief? {
        guard SessionDebrief.scoreRange.contains(debrief.score) else { return nil }
        let known = facts.factIDs
        let knownText = facts.facts.map(\.text)
        let cap = SessionDebrief.maxBulletsPerList
        func grounded(_ claims: [CoachClaim]) -> [CoachClaim] {
            Array(claims.filter { $0.isGrounded(in: known, numbersFrom: knownText) }.prefix(cap))
        }
        let wentWell = grounded(debrief.wentWell)
        let watch = grounded(debrief.watch)
        let tryNext = grounded(debrief.tryNext)
        guard !(wentWell.isEmpty && watch.isEmpty && tryNext.isEmpty) else { return nil }
        return SessionDebrief(score: debrief.score, wentWell: wentWell, watch: watch, tryNext: tryNext)
    }
}

/// The deterministic debrief, from thresholds alone — what the card shows when the on-device
/// model is off or unavailable. Same struct, same citations, so `DebriefValidator` accepts it
/// unchanged (a test pins that).
public enum DebriefRules {
    /// Volume within this fraction of last time counts as "held steady".
    static let steadyVolumeBand = 0.05
    /// An RPE rise past this, at steady volume, is worth watching.
    static let rpeDriftThreshold = 0.5
    static let baseScore = 6

    private typealias Fact = SessionSummaryFacts.FactID

    public static func debrief(from facts: SessionSummaryFacts) -> SessionDebrief {
        var score = baseScore
        var wentWell = wins(from: facts, score: &score)
        var watch = concerns(from: facts, score: &score)
        var tryNext = nextSteps(from: facts)
        if wentWell.isEmpty {
            let text = "You showed up and finished \(facts.setsDone) sets."
            wentWell.append(CoachClaim(text: text, citedFactIDs: [Fact.sets]))
        }
        if tryNext.isEmpty {
            let text = "Repeat this session and aim to match every set."
            tryNext.append(CoachClaim(text: text, citedFactIDs: [Fact.sets]))
        }
        let range = SessionDebrief.scoreRange
        let cap = SessionDebrief.maxBulletsPerList
        watch = Array(watch.prefix(cap))
        return SessionDebrief(
            score: min(max(score, range.lowerBound), range.upperBound),
            wentWell: Array(wentWell.prefix(cap)), watch: watch, tryNext: Array(tryNext.prefix(cap))
        )
    }

    private static func wins(from facts: SessionSummaryFacts, score: inout Int) -> [CoachClaim] {
        var wins: [CoachClaim] = []
        if let name = facts.personalRecords.first {
            score += 2
            wins.append(CoachClaim(text: "New personal record on \(name).", citedFactIDs: [Fact.prs]))
        }
        if let change = facts.volumeChangeFraction {
            if change > steadyVolumeBand {
                score += 1
                let text = "More total work than last time."
                wins.append(CoachClaim(text: text, citedFactIDs: [Fact.volumeChange]))
            } else if change >= -steadyVolumeBand {
                let text = "Volume held steady with last time."
                wins.append(CoachClaim(text: text, citedFactIDs: [Fact.volumeChange]))
            }
        }
        if let name = facts.e1rmUp.first {
            wins.append(CoachClaim(text: "Strength moved up on \(name).", citedFactIDs: [Fact.e1rmUp]))
        }
        return wins
    }

    private static func concerns(from facts: SessionSummaryFacts, score: inout Int) -> [CoachClaim] {
        var concerns: [CoachClaim] = []
        if let change = facts.volumeChangeFraction, change < -steadyVolumeBand {
            score -= 1
            let text = "Volume dipped against your last run."
            concerns.append(CoachClaim(text: text, citedFactIDs: [Fact.volumeChange]))
        }
        if facts.skippedSets > 0 {
            score -= 1
            concerns.append(CoachClaim(text: "Some planned sets were skipped.", citedFactIDs: [Fact.skipped]))
        }
        if facts.setsBelowLast > 0 {
            let text = "A few sets came up short of last time."
            concerns.append(CoachClaim(text: text, citedFactIDs: [Fact.belowLast]))
        }
        if let drift = facts.rpeDrift, drift > rpeDriftThreshold {
            score -= 1
            let text = "Sets felt harder than last time at similar work."
            concerns.append(CoachClaim(text: text, citedFactIDs: [Fact.rpeDrift]))
        }
        if let name = facts.e1rmDown.first {
            concerns.append(CoachClaim(text: "Strength slipped on \(name).", citedFactIDs: [Fact.e1rmDown]))
        }
        return concerns
    }

    private static func nextSteps(from facts: SessionSummaryFacts) -> [CoachClaim] {
        var steps: [CoachClaim] = []
        if facts.skippedSets > 0 {
            let text = "Plan the full set count next time, or trim the plan."
            steps.append(CoachClaim(text: text, citedFactIDs: [Fact.skipped]))
        }
        if let drift = facts.rpeDrift, drift > rpeDriftThreshold {
            let text = "Keep the load and watch RPE next session before adding weight."
            steps.append(CoachClaim(text: text, citedFactIDs: [Fact.rpeDrift]))
        }
        return steps
    }
}
