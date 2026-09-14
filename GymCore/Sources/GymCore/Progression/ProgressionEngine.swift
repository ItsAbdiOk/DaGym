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

/// Everything one rule function needs, bundled so each stays a short function.
struct RuleContext {
    var planned: [PlannedSetSpec]
    var history: [ExerciseHistoryEntry]
    var baseline: ExerciseHistoryEntry?
    var stall: StallState
    var bodyweightKg: Double?
    var trainingMaxKg: Double?
    var weekInCycle: Int
    var unit: WeightUnit
    var grid: LoadGrid
    var cycleIndex: Int?
    var trainingMaxIncrementKg: Double
    var perSide: Bool = false

    /// Rep targets move one at a time, or two when reps are per-side totals.
    var repStep: Int { perSide ? 2 : 1 }

    /// The plan's target weight for the first working set, when it names one.
    var planTargetWeightKg: Double? {
        planned.first { $0.kind.countsTowardStats }?.targetWeightKg
    }

    /// Per-side totals stay even: 17 becomes 18. Identity otherwise.
    func evenReps(_ reps: Int) -> Int {
        perSide && !reps.isMultiple(of: 2) ? reps + 1 : reps
    }

    var baselineWorkingSets: [HistorySet] { baseline?.workingSets ?? [] }

    func rounded(_ target: Double) -> Double { grid.nearest(target) }

    func roundedDown(_ target: Double) -> Double { grid.nearestBelow(target) }

    /// `current + incrementKg` on the grid, guaranteed to land above `current`
    /// (an increment smaller than the grid step still moves one grid step) and
    /// capped at `maxSessionIncreaseFraction` — the grid's single step always wins,
    /// so a 12 kg dumbbell can still go to 14. An unloaded (0 kg) start has no
    /// fraction to cap by, so the first load is the increment itself.
    func increased(_ current: Double, by incrementKg: Double) -> Double {
        let oneStep = grid.nearestAbove(current)
        let candidate = rounded(current + incrementKg)
        let raised = candidate > current + 0.001 ? candidate : oneStep
        guard current > 0.001 else { return raised }
        let cap = roundedDown(current * (1 + TrainingConstants.maxSessionIncreaseFraction))
        return min(raised, max(oneStep, cap))
    }

    /// Clamps a deload candidate onto the grid between its lightest positive load and
    /// the heaviest load strictly under `weightKg` — a deload is always a real decrease
    /// and never zero or negative. Nil when no such load exists (an empty bar, the
    /// lightest dumbbell): hold instead of deloading.
    func deloadClamped(_ candidate: Double, below weightKg: Double) -> Double? {
        // Wider than the grid's own rounding slack, so "just under" isn't snapped back up.
        let epsilon = 0.01
        if case .free = grid {
            return candidate > epsilon && candidate < weightKg - epsilon ? candidate : nil
        }
        let heaviestBelow = grid.nearestBelow(weightKg - epsilon)
        let lightest = grid.nearestAbove(0)
        guard heaviestBelow > epsilon, heaviestBelow < weightKg - epsilon,
              lightest <= heaviestBelow + epsilon else { return nil }
        return min(max(candidate, lightest), heaviestBelow)
    }

    /// The hold for a deload that has nowhere to go: same weight, `.repeat`, and the
    /// miss streak kept so the advice stands until the lifter changes something.
    func lightestLoadPrescribed(weightKg: Double, misses: Int, baselineDate: Date?) -> Prescribed {
        let title = "Already at the lightest load"
        let sets = planned.map {
            Prescription(
                weightKg: weightKg, reps: $0.targetReps ?? 0, durationSeconds: $0.targetSeconds,
                previous: nil, reason: title
            )
        }
        return Prescribed(
            sets: sets,
            reason: PrescriptionReason(
                title: title,
                body: "\(misses) sessions in a row missed at \(formatted(kg: weightKg)) and there's " +
                    "nothing lighter on this equipment — try a lighter variation.",
                kind: .repeat
            ),
            stall: stall.advancing(misses: misses, weightKg: weightKg),
            trainingMaxKg: trainingMaxKg, previousDate: baselineDate
        )
    }

    /// A kg value in the user's unit with its symbol: "82.5 kg", "135 lb".
    func formatted(kg: Double) -> String {
        "\(unit.format(kg: kg)) \(unit.symbol)"
    }

    /// "+5 lb" — the jump that actually happened, not the rule's nominal increment.
    ///
    /// At the top of the plate rack (or the last dumbbell on the rack) the grid has nothing
    /// above the current load, so `increased` hands back the weight it was given and the jump
    /// is zero. "+0 kg" read as a raise that wasn't; say what actually happens instead.
    func increaseTitle(from oldKg: Double, to newKg: Double) -> String {
        let delta = newKg - oldKg
        guard delta > 0.001 else { return "Repeat \(formatted(kg: newKg))" }
        return "+\(formatted(kg: delta))"
    }

    /// A "from your plan"/"first time" prescription for when there is no baseline to build from.
    func firstTimePrescribed(weightKg: Double = 0) -> Prescribed {
        let sets = planned.map {
            Prescription(
                weightKg: weightKg, reps: $0.targetReps ?? 0, durationSeconds: $0.targetSeconds,
                previous: nil, reason: "First time — enter a weight"
            )
        }
        return Prescribed(
            sets: sets,
            reason: PrescriptionReason(
                title: "First time",
                body: "No history yet for this exercise — enter your own numbers.",
                kind: .firstTime
            ),
            stall: stall,
            trainingMaxKg: trainingMaxKg
        )
    }

    /// Repeat the baseline weight without touching the miss streak — for sessions the
    /// rule can't judge (no target set, no RPE logged) rather than for misses.
    func holdPrescribed(weightKg: Double, title: String, body: String, baselineDate: Date?) -> Prescribed {
        let sets = planned.map {
            Prescription(
                weightKg: weightKg, reps: $0.targetReps ?? 0, durationSeconds: $0.targetSeconds,
                previous: nil, reason: title
            )
        }
        return Prescribed(
            sets: sets, reason: PrescriptionReason(title: title, body: body, kind: .repeat),
            stall: stall, trainingMaxKg: trainingMaxKg, previousDate: baselineDate
        )
    }
}
