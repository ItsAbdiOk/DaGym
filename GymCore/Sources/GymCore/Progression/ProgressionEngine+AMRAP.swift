import Foundation

extension ProgressionEngine {
    /// Linear + AMRAP top set (plan.md §7): the last working set is an AMRAP.
    /// The straight sets must hit their targets first; then the AMRAP decides:
    /// double the target reps → double increment, at least the target → normal
    /// increment, below target → repeat, and a second miss in a row backs off 10 %.
    static func prescribeLinearAMRAP(_ context: RuleContext, incrementKg: Double) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = baseline.workingSets
        guard let weightKg = workingSets.first?.weightKg, let lastSet = workingSets.last else {
            return context.firstTimePrescribed()
        }
        let stall = resetIfWeightChanged(context.stall, currentWeightKg: weightKg)
        guard lastSet.kind == .amrap else {
            return context.holdPrescribed(
                weightKg: weightKg, title: "Repeat \(context.formatted(kg: weightKg))",
                body: "No AMRAP set was logged last session — log the last set as AMRAP so this rule " +
                    "can judge it.",
                baselineDate: baseline.date
            )
        }

        let straightSets = workingSets.dropLast().filter { $0.kind != .amrap }
        let straightPlanned = context.planned.filter { $0.kind.countsTowardStats && $0.kind != .amrap }
        if setsHitTarget(workingSets: Array(straightSets), planned: straightPlanned) == .missedReps {
            let summary = performanceSummary(Array(straightSets))
            return linearMissForAMRAP(
                context, weightKg: weightKg, incrementKg: incrementKg, stall: stall,
                body: "Your straight sets missed (\(summary)) last session — same weight again."
            )
        }

        let plannedTarget = context.planned.last(where: { $0.kind == .amrap })?.targetReps
            ?? context.planned.last(where: { $0.kind.countsTowardStats })?.targetReps
        guard let target = plannedTarget, target > 0 else {
            return context.holdPrescribed(
                weightKg: weightKg, title: "Repeat \(context.formatted(kg: weightKg))",
                body: "No rep target is set for the AMRAP set, so the rule can't judge last session " +
                    "— add target reps to progress automatically.",
                baselineDate: baseline.date
            )
        }
        let amrapReps = lastSet.reps
        let summary = "\(amrapReps) reps on the AMRAP set (target \(target))"
        switch amrapOutcome(amrapReps: amrapReps, target: target) {
        case .double:
            let newWeight = context.increased(
                weightKg, by: incrementKg * TrainingConstants.amrapDoubleIncrementMultiple
            )
            return amrapIncrease(context, from: weightKg, to: newWeight, summary: summary, stall: stall)
        case .normal:
            let newWeight = context.increased(weightKg, by: incrementKg)
            return amrapIncrease(context, from: weightKg, to: newWeight, summary: summary, stall: stall)
        case .miss:
            return linearMissForAMRAP(
                context, weightKg: weightKg, incrementKg: incrementKg, stall: stall,
                body: "You got \(summary) last session — same weight again."
            )
        }
    }

    private static func amrapIncrease(
        _ context: RuleContext, from weightKg: Double, to newWeight: Double, summary: String,
        stall: StallState
    ) -> Prescribed {
        prescribedResult(
            context, weightKg: newWeight,
            reason: PrescriptionReason(
                title: context.increaseTitle(from: weightKg, to: newWeight),
                body: "You got \(summary) last session.", kind: .increase
            ),
            stall: stall.advancing(misses: 0, weightKg: newWeight),
            baselineDate: context.baseline?.date
        )
    }

    /// A miss counts toward the AMRAP back-off: repeat first, back off 10 % on the
    /// `amrapMissesBeforeReset`th consecutive miss (rounded down, always below).
    private static func linearMissForAMRAP(
        _ context: RuleContext, weightKg: Double, incrementKg: Double, stall: StallState, body: String
    ) -> Prescribed {
        let baselineDate = context.baseline?.date
        let misses = stall.consecutiveMisses + 1
        guard misses >= TrainingConstants.amrapMissesBeforeReset else {
            return prescribedResult(
                context, weightKg: weightKg,
                reason: PrescriptionReason(
                    title: "Repeat \(context.formatted(kg: weightKg))", body: body, kind: .repeat
                ),
                stall: stall.advancing(misses: misses, weightKg: weightKg),
                baselineDate: baselineDate
            )
        }
        let byFraction = context.roundedDown(weightKg * TrainingConstants.amrapMissFraction)
        let candidate = min(byFraction, context.roundedDown(weightKg - max(incrementKg, 0)))
        guard let newWeight = context.deloadClamped(candidate, below: weightKg) else {
            return context.lightestLoadPrescribed(
                weightKg: weightKg, misses: misses, baselineDate: baselineDate
            )
        }
        return prescribedResult(
            context, weightKg: newWeight,
            reason: PrescriptionReason(
                title: "Back off to \(context.formatted(kg: newWeight))",
                body: "\(misses) sessions in a row missed — dropping 10% to rebuild.", kind: .deload
            ),
            stall: stall.advancing(misses: 0, weightKg: newWeight), baselineDate: baselineDate
        )
    }

    private enum AMRAPOutcome: Equatable {
        case double, normal, miss
    }

    private static func amrapOutcome(amrapReps: Int, target: Int) -> AMRAPOutcome {
        let doubleTarget = Double(target) * TrainingConstants.amrapDoubleIncrementMultiple
        if Double(amrapReps) >= doubleTarget {
            return .double
        }
        if amrapReps < target {
            return .miss
        }
        return .normal
    }
}
