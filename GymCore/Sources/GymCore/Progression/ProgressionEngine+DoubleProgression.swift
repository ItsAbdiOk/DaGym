import Foundation

extension ProgressionEngine {
    /// Double progression (plan.md §7): climb reps within [low, high]. Once every
    /// set reaches `high`, add weight and drop back to `low` reps. Climbing
    /// within the range is progress, not a stall — but the weakest set failing
    /// to beat the run's best at this weight for `doubleProgressionMissesBeforeDeload`
    /// sessions is one: drop one increment and ask for `high` again (the rung it
    /// last succeeded on). Fewer sets than planned can't be judged — hold.
    /// Per-side totals step by 2 and the range is rounded up to even.
    static func prescribeDoubleProgression(
        _ context: RuleContext, low rawLow: Int, high rawHigh: Int, incrementKg: Double
    ) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = context.baselineWorkingSets
        guard let weightKg = workingSets.first?.weightKg, !workingSets.isEmpty else {
            return context.firstTimePrescribed()
        }
        let low = context.evenReps(rawLow)
        let high = context.evenReps(rawHigh)

        let summary = performanceSummary(workingSets)
        let stall = resetIfWeightChanged(context.stall, currentWeightKg: weightKg)
        let plannedCount = context.planned.filter { $0.kind.countsTowardStats }.count
        if plannedCount > 0, workingSets.count < plannedCount {
            return doubleProgressionPartialHold(context, range: low...high, weightKg: weightKg, stall: stall)
        }
        let judged = plannedCount > 0 ? Array(workingSets.prefix(plannedCount)) : workingSets
        if judged.allSatisfy({ $0.reps >= high }) {
            let newWeight = context.increased(weightKg, by: incrementKg)
            return doubleProgressionResult(context, RuleOutcome(
                weightKg: newWeight, reps: low,
                reason: PrescriptionReason(
                    title: context.increaseTitle(from: weightKg, to: newWeight),
                    body: "You hit \(summary) — the top of your rep range — last session.", kind: .increase
                ),
                stall: stall.advancing(misses: 0, weightKg: newWeight), baselineDate: baseline.date
            ))
        }

        let weakestReps = judged.map(\.reps).min() ?? low
        // A session at this weight that didn't beat the run's best weakest set counts as a miss.
        // The *first* session at a weight does not: it has nothing to beat, it sets the bar the
        // following sessions have to clear. Counting it (as this did) meant
        // `doubleProgressionMissesBeforeDeload` sessions really bought the lifter one fewer real
        // chance to add a rep than the constant — and than the deload's own copy — claims.
        // State persisted before `bestWeakestReps` existed only knows last session's weakest set.
        let runBest = stall.bestWeakestReps ?? stall.lastWeakestReps
        let improved = runBest.map { weakestReps > $0 } ?? false
        let bestWeakestReps = improved ? weakestReps : (runBest ?? weakestReps)
        let misses = improved || runBest == nil ? 0 : stall.consecutiveMisses + 1
        if misses >= TrainingConstants.doubleProgressionMissesBeforeDeload {
            return doubleProgressionDeload(
                context, high: high, weightKg: weightKg, incrementKg: incrementKg, stall: stall
            )
        }

        let nextReps = min(high, max(low, context.evenReps(weakestReps + context.repStep)))
        return doubleProgressionResult(context, RuleOutcome(
            weightKg: weightKg, reps: nextReps,
            reason: PrescriptionReason(
                title: "\(nextReps) reps",
                body: "You hit \(summary) last session — aim for \(nextReps) this time.", kind: .increase
            ),
            stall: stall.advancing(
                misses: misses, weightKg: weightKg, weakestReps: weakestReps, bestWeakestReps: bestWeakestReps
            ),
            baselineDate: baseline.date
        ))
    }

    private static func doubleProgressionPartialHold(
        _ context: RuleContext, range: ClosedRange<Int>, weightKg: Double, stall: StallState
    ) -> Prescribed {
        let planned = context.planned.filter { $0.kind.countsTowardStats }
        let logged = context.baselineWorkingSets
        let planReps = planned.first?.targetReps ?? logged.map(\.reps).max() ?? range.lowerBound
        return doubleProgressionResult(context, RuleOutcome(
            weightKg: weightKg, reps: planReps.clamped(to: range),
            reason: PrescriptionReason(
                title: "Repeat \(context.formatted(kg: weightKg))",
                body: "Only \(logged.count) of \(planned.count) sets were logged last session " +
                    "— same weight again.",
                kind: .repeat
            ),
            stall: stall, baselineDate: context.baseline?.date
        ))
    }

    /// One increment down (never below the grid's lightest load) and `high` reps again;
    /// with nothing lighter to go to, hold instead. This session is the miss that tipped it.
    private static func doubleProgressionDeload(
        _ context: RuleContext, high: Int, weightKg: Double, incrementKg: Double, stall: StallState
    ) -> Prescribed {
        let misses = stall.consecutiveMisses + 1
        let baselineDate = context.baseline?.date
        let candidate = context.roundedDown(weightKg - max(incrementKg, 0.001))
        guard let newWeight = context.deloadClamped(candidate, below: weightKg) else {
            return context.lightestLoadPrescribed(
                weightKg: weightKg, misses: misses, baselineDate: baselineDate
            )
        }
        let summary = performanceSummary(context.baselineWorkingSets)
        return doubleProgressionResult(context, RuleOutcome(
            weightKg: newWeight, reps: high,
            reason: PrescriptionReason(
                title: "Deload to \(context.formatted(kg: newWeight))",
                body: "\(misses) sessions at \(context.formatted(kg: weightKg)) without adding a rep " +
                    "(last: \(summary)) — drop back and own \(high) reps again.",
                kind: .deload
            ),
            stall: stall.advancing(misses: 0, weightKg: newWeight), baselineDate: baselineDate
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

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
