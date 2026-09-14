import Foundation

extension ProgressionEngine {
    /// Bodyweight rule (plan.md §7): add reps up to a ceiling, then add a set
    /// (up to a max), then suggest a harder variation or added load. Sessions are
    /// judged against the reps the engine actually asked for last time
    /// (`stall.lastTargetReps`, else the plan's target): every set at or above
    /// them climbs, any set below repeats the same ask. A plan edited since
    /// outranks that memory. A new set starts back at the plan's base reps. The
    /// set count is sized from the ladder the engine is itself on
    /// (`stall.lastTargetSets`, else the plan's count), not from however many sets
    /// were logged: a partial session holds, extra sets don't count. A plan re-sized
    /// since outranks that memory too. Remembering the count is what makes the ladder
    /// climb at all — sized from the plan alone, "+1 set" was re-proposed off the
    /// plan's own count every session, so `maxSets` was unreachable and the
    /// harder-variation hand-off never fired. Per-side totals step by 2.
    static func prescribeBodyweight(_ context: RuleContext, repCeiling: Int, maxSets: Int) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = context.baselineWorkingSets
        guard !workingSets.isEmpty else { return context.firstTimePrescribed() }
        let addedWeightKg = workingSets.first?.weightKg ?? 0
        let workingPlanned = context.planned.filter { $0.kind.countsTowardStats }
        let planSets = workingPlanned.isEmpty ? nil : workingPlanned.count
        let ceiling = context.evenReps(repCeiling)

        let planTarget = workingPlanned.first?.targetReps
        let seenPlanTarget = context.stall.lastPlanTargetReps
        let planEdited = planTarget != nil && seenPlanTarget != nil && planTarget != seenPlanTarget
        let remembered = planEdited ? nil : context.stall.lastTargetReps
        let asked = remembered ?? planTarget ?? workingSets.map(\.reps).min() ?? ceiling
        // The rung of the set ladder the engine last asked for, unless the plan itself has been
        // re-sized since — then the plan wins, the same way it does for the rep target.
        let seenPlanSets = context.stall.lastPlanTargetSets
        let planSetsEdited = planSets != nil && seenPlanSets != nil && planSets != seenPlanSets
        let rememberedSets = planSetsEdited ? nil : context.stall.lastTargetSets
        let plannedCount = max(1, rememberedSets ?? planSets ?? workingSets.count)
        var outcome = BodyweightOutcome(
            addedWeightKg: addedWeightKg, setCount: plannedCount, reps: asked,
            reason: PrescriptionReason(title: "Repeat \(plannedCount)×\(asked)", body: "", kind: .repeat),
            planTarget: planTarget, planSets: planSets, baselineDate: baseline.date
        )

        if workingSets.count < plannedCount {
            outcome.reason.body = "Only \(workingSets.count) of \(plannedCount) sets were logged last " +
                "session — same plan again."
            return bodyweightResult(context, outcome)
        }

        let judged = Array(workingSets.prefix(plannedCount))
        let summary = performanceSummary(judged)
        let weakestReps = judged.map(\.reps).min() ?? 0
        if weakestReps >= ceiling {
            if plannedCount < maxSets {
                outcome.setCount = plannedCount + 1
                outcome.reps = max(1, planTarget ?? ceiling)
                outcome.reason = PrescriptionReason(
                    title: "+1 set",
                    body: "You hit \(summary) — add another set and build it back up from " +
                        "\(outcome.reps) reps.",
                    kind: .increase
                )
                return bodyweightResult(context, outcome)
            }
            outcome.reps = ceiling
            outcome.reason = PrescriptionReason(
                title: "Try a harder variation",
                body: "You maxed out \(maxSets) sets of \(ceiling) — add load or a harder variation.",
                kind: .plan
            )
            return bodyweightResult(context, outcome)
        }
        guard weakestReps >= asked else {
            outcome.reason.body = "You got \(summary) of the \(asked) reps asked last session — same " +
                "target again."
            return bodyweightResult(context, outcome)
        }

        outcome.reps = min(ceiling, context.evenReps(max(asked, weakestReps) + context.repStep))
        outcome.reason = PrescriptionReason(
            title: "\(outcome.reps) reps",
            body: "You hit \(summary) last session — aim for \(outcome.reps) this time.", kind: .increase
        )
        return bodyweightResult(context, outcome)
    }

    private static func bodyweightResult(_ context: RuleContext, _ outcome: BodyweightOutcome) -> Prescribed {
        let sets = (0..<outcome.setCount).map { _ in
            Prescription(
                weightKg: outcome.addedWeightKg, reps: outcome.reps, durationSeconds: nil,
                previous: nil, reason: outcome.reason.title
            )
        }
        var stall = context.stall
        stall.lastTargetReps = outcome.reps
        stall.lastPlanTargetReps = outcome.planTarget
        stall.lastTargetSets = outcome.setCount
        stall.lastPlanTargetSets = outcome.planSets
        return Prescribed(
            sets: sets, reason: outcome.reason, stall: stall, trainingMaxKg: context.trainingMaxKg,
            previousDate: outcome.baselineDate
        )
    }
}

/// Bundled result for the bodyweight rule, whose set count can itself change.
private struct BodyweightOutcome {
    var addedWeightKg: Double
    var setCount: Int
    var reps: Int
    var reason: PrescriptionReason
    var planTarget: Int?
    var planSets: Int?
    var baselineDate: Date?
}
