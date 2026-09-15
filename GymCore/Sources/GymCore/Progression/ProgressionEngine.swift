import Foundation

/// One planned set from the routine, before it's been filled with numbers.
public struct PlannedSetSpec: Hashable, Sendable {
    public var kind: SetKind
    public var targetReps: Int?
    public var targetSeconds: Int?
    /// Tracked target RPE for this set, when the rule cares about effort
    /// (e.g. linear only counts a set as "hit" when RPE stayed at or below this).
    public var targetRPE: Double?
    /// The plan's own target weight for this set, when one is set. No rule prescribes from
    /// it — the engine works off history — but it is carried through so the judgement can
    /// record what the plan said (`StallState.lastPlanTargetWeightKg`), which is how the app
    /// layer tells a changed target apart from an unrelated routine save.
    public var targetWeightKg: Double?

    public init(
        kind: SetKind, targetReps: Int? = nil, targetSeconds: Int? = nil, targetRPE: Double? = nil,
        targetWeightKg: Double? = nil
    ) {
        self.kind = kind
        self.targetReps = targetReps
        self.targetSeconds = targetSeconds
        self.targetRPE = targetRPE
        self.targetWeightKg = targetWeightKg
    }
}

/// Why the engine chose these numbers, for the "why" explainer card.
public struct PrescriptionReason: Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case increase
        case `repeat`
        case deload
        case plan
        case firstTime
    }

    /// Short headline, e.g. "+2.5 kg".
    public var title: String
    /// One sentence of plain-language evidence, e.g. "You hit 3×8 at RPE 7 last Tuesday."
    public var body: String
    public var kind: Kind

    public init(title: String, body: String, kind: Kind) {
        self.title = title
        self.body = body
        self.kind = kind
    }
}

/// The engine's full output for one exercise: the numbers to prefill, why,
/// and the updated persisted state.
public struct Prescribed: Sendable {
    public var sets: [Prescription]
    public var reason: PrescriptionReason
    public var stall: StallState
    /// The (possibly bumped) training max for the caller to persist. The cycle it was
    /// bumped in rides along in `stall.trainingMaxCycle`.
    public var trainingMaxKg: Double?
    /// The baseline session's date, for the caller to format into the reason text.
    public var previousDate: Date?

    public init(
        sets: [Prescription],
        reason: PrescriptionReason,
        stall: StallState,
        trainingMaxKg: Double? = nil,
        previousDate: Date? = nil
    ) {
        self.sets = sets
        self.reason = reason
        self.stall = stall
        self.trainingMaxKg = trainingMaxKg
        self.previousDate = previousDate
    }
}

/// Computes next-session numbers from a routine exercise's progression rule
/// and its logged history (plan.md §6.5, §7).
public enum ProgressionEngine {
    /// - Parameters:
    ///   - history: newest first. A planned deload is excluded as the baseline
    ///     future progression builds from, though it still appears in the list.
    ///   - bar/plates/collarsKg: the barbell inventory, used only when `grid` is nil.
    ///   - grid: the equipment's rounding grid. Pass `.plates` for a barbell,
    ///     `.step(2)` for dumbbells, `.step(5)` for a machine stack, `.free` for
    ///     bodyweight/assisted work. When nil the equipment is unknown: the bar
    ///     inventory is used at or above the bar, and loads lighter than the bar
    ///     are stepped by the smallest plate pair rather than snapped up to it.
    ///   - cycleIndex: for `.percentOfTrainingMax`, which cycle of the wave this
    ///     is (1-based, increments every time week 4 rolls to week 1). The TM is
    ///     bumped only when this is greater than `stall.trainingMaxCycle`; nil
    ///     never bumps.
    ///   - trainingMaxIncrementKg: the per-cycle TM bump for this lift (2.5 kg
    ///     upper / 5 kg lower); defaults to `TrainingConstants.trainingMaxUpperIncrementKg`.
    ///   - perSide: the exercise is unilateral and reps are logged as totals, so rep
    ///     targets step by 2 and stay even (plan.md §7).
    public static func prescribe(
        rule: ProgressionRule,
        planned: [PlannedSetSpec],
        history: [ExerciseHistoryEntry],
        stall: StallState,
        bodyweightKg: Double? = nil,
        trainingMaxKg: Double? = nil,
        weekInCycle: Int? = nil,
        unit: WeightUnit = .kg,
        bar: Bar = .olympic,
        plates: [PlateStock] = PlateStock.standardKg,
        collarsKg: Double = 0,
        grid: LoadGrid? = nil,
        cycleIndex: Int? = nil,
        trainingMaxIncrementKg: Double? = nil,
        perSide: Bool = false
    ) -> Prescribed {
        let context = RuleContext(
            planned: planned,
            history: history,
            baseline: history.first { !$0.wasPlannedDeload },
            stall: stall,
            bodyweightKg: bodyweightKg,
            trainingMaxKg: trainingMaxKg,
            weekInCycle: weekInCycle ?? 1,
            unit: unit,
            grid: grid ?? .unknown(bar: bar, plates: plates, collarsKg: collarsKg),
            cycleIndex: cycleIndex,
            trainingMaxIncrementKg: trainingMaxIncrementKg ?? TrainingConstants.trainingMaxUpperIncrementKg,
            perSide: perSide
        )
        var result = dispatch(rule, context)
        // Stamped centrally, for every rule: what the plan's working target weight said at the
        // moment this judgement was made. The app layer compares the plan's *current* target
        // against it to tell a real target edit (or an approved Coach deload) apart from an
        // unrelated routine save, which used to be indistinguishable because both only moved
        // `RoutineModel.updatedAt`.
        result.stall.lastPlanTargetWeightKg = context.planTargetWeightKg
        return result
    }

    private static func dispatch(_ rule: ProgressionRule, _ context: RuleContext) -> Prescribed {
        switch rule {
        case .linear(let incrementKg):
            return prescribeLinear(context, incrementKg: incrementKg)
        case .doubleProgression(let low, let high, let incrementKg):
            return prescribeDoubleProgression(context, low: low, high: high, incrementKg: incrementKg)
        case .linearAMRAP(let incrementKg):
            return prescribeLinearAMRAP(context, incrementKg: incrementKg)
        case .rpeBased(let targetRPE):
            return prescribeRPEBased(context, targetRPE: targetRPE)
        case .percentOfTrainingMax(let scheme):
            return prescribeTrainingMax(context, scheme: scheme)
        case .bodyweight(let repCeiling, let maxSets):
            return prescribeBodyweight(context, repCeiling: repCeiling, maxSets: maxSets)
        case .assisted(let stepKg):
            return prescribeAssisted(context, stepKg: stepKg)
        case .timed(let stepSeconds):
            return prescribeTimed(context, stepSeconds: stepSeconds)
        }
    }
}
