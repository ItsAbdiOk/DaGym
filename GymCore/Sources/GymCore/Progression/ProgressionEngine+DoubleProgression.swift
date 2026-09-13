import Foundation

extension ProgressionEngine {
    /// Double progression (plan.md §7): climb reps within [low, high]. Once every
    /// set reaches `high`, add weight and drop back to `low` reps. Climbing
    /// within the range is progress, not a stall — but the weakest set failing
    /// to improve for `doubleProgressionMissesBeforeDeload` sessions at the same
    /// weight is one: drop one increment and ask for `high` again (the rung it
    /// last succeeded on).
    static func prescribeDoubleProgression(
        _ context: RuleContext, low: Int, high: Int, incrementKg: Double
    ) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = context.baselineWorkingSets
        guard let weightKg = workingSets.first?.weightKg, !workingSets.isEmpty else {
            return context.firstTimePrescribed()
        }

        let summary = performanceSummary(workingSets)
        if workingSets.allSatisfy({ $0.reps >= high }) {
            let newWeight = context.increased(weightKg, by: incrementKg)
            return doubleProgressionResult(context, RuleOutcome(
                weightKg: newWeight, reps: low,
                reason: PrescriptionReason(
                    title: context.increaseTitle(from: weightKg, to: newWeight),
                    body: "You hit \(summary) — the top of your rep range — last session.", kind: .increase
                ),
                stall: StallState(consecutiveMisses: 0, lastWeightKg: newWeight), baselineDate: baseline.date
            ))
        }

        let stall = resetIfWeightChanged(context.stall, currentWeightKg: weightKg)
        let weakestReps = workingSets.map(\.reps).min() ?? low
        // A session at this weight that didn't add a rep on the weakest set counts; the first
        // session at a weight counts as one too, so "3 sessions without a rep" is literal.
        let improved = stall.lastWeakestReps.map { weakestReps > $0 } ?? false
        let misses = improved ? 0 : stall.consecutiveMisses + 1
        if misses >= TrainingConstants.doubleProgressionMissesBeforeDeload {
            let newWeight = context.roundedDown(weightKg - max(incrementKg, 0.001))
            return doubleProgressionResult(context, RuleOutcome(
                weightKg: newWeight, reps: high,
                reason: PrescriptionReason(
                    title: "Deload to \(context.formatted(kg: newWeight))",
                    body: "\(misses) sessions at \(context.formatted(kg: weightKg)) without adding a rep " +
                        "(last: \(summary)) — drop back and own \(high) reps again.",
                    kind: .deload
                ),
                stall: StallState(consecutiveMisses: 0, lastWeightKg: newWeight), baselineDate: baseline.date
            ))
        }

        let nextReps = min(high, max(low, weakestReps + 1))
        return doubleProgressionResult(context, RuleOutcome(
            weightKg: weightKg, reps: nextReps,
            reason: PrescriptionReason(
                title: "\(nextReps) reps",
                body: "You hit \(summary) last session — aim for \(nextReps) this time.", kind: .increase
            ),
            stall: StallState(
                consecutiveMisses: misses, lastWeightKg: weightKg, lastWeakestReps: weakestReps
            ),
            baselineDate: baseline.date
        ))
    }

    private static func doubleProgressionResult(
        _ context: RuleContext, _ outcome: RuleOutcome
    ) -> Prescribed {
        let sets = context.planned.map { spec in
            Prescription(
                weightKg: outcome.weightKg, reps: outcome.reps, durationSeconds: spec.targetSeconds,
                previous: nil, reason: outcome.reason.title
            )
        }
        return Prescribed(
            sets: sets, reason: outcome.reason, stall: outcome.stall, trainingMaxKg: context.trainingMaxKg,
            previousDate: outcome.baselineDate
        )
    }
}

/// A rule's computed weight/reps and the reason/stall/date that go with them,
/// bundled so result-building helpers don't blow the parameter-count limit.
struct RuleOutcome {
    var weightKg: Double
    var reps: Int
    var reason: PrescriptionReason
    var stall: StallState
    var baselineDate: Date?
}
