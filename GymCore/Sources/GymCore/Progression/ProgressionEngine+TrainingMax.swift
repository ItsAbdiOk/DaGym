import Foundation

extension ProgressionEngine {
    /// Percent / training-max rule (plan.md §7): a 4-week 5/3/1-style wave off
    /// a rolling training max. TM defaults to 90 % of the best recent e1RM when
    /// unset, and bumps by the lift's increment once per cycle — only when the
    /// caller's `cycleIndex` has moved past `stall.trainingMaxCycle`, never on
    /// every week-1 call. The bump is capped by 90 % of the best AMRAP e1RM
    /// since the last bump, so a TM that has run ahead of the lifter holds.
    static func prescribeTrainingMax(_ context: RuleContext, scheme: WaveScheme) -> Prescribed {
        guard let weekSets = scheme.weeks[context.weekInCycle], !weekSets.isEmpty else {
            return context.holdPrescribed(
                weightKg: 0, title: "Week \(context.weekInCycle)",
                body: "This wave has no week \(context.weekInCycle) — check the program's week count.",
                baselineDate: context.baseline?.date
            )
        }
        guard let resolved = resolvedTrainingMax(context) else { return context.firstTimePrescribed() }

        let sets = weekSets.map { weekSet in
            Prescription(
                weightKg: context.rounded(resolved.trainingMaxKg * weekSet.percent), reps: weekSet.reps,
                durationSeconds: nil, previous: nil,
                reason: weekSet.isAMRAP ? "AMRAP — beat this" : "Week \(context.weekInCycle) target"
            )
        }
        let percents = weekSets.map { "\(Int(($0.percent * 100).rounded()))%" }.joined(separator: "/")
        var stall = context.stall
        stall.trainingMaxCycle = resolved.cycle
        return Prescribed(
            sets: sets,
            reason: PrescriptionReason(
                title: "Week \(context.weekInCycle)",
                body: "Training max \(context.formatted(kg: resolved.trainingMaxKg)) — " +
                    "\(percents) of TM this week.", kind: .plan
            ),
            stall: stall, trainingMaxKg: resolved.trainingMaxKg, previousDate: context.baseline?.date
        )
    }

    /// The TM to program off this cycle and the cycle it belongs to.
    private static func resolvedTrainingMax(_ context: RuleContext) -> (trainingMaxKg: Double, cycle: Int?)? {
        if let trainingMaxKg = context.trainingMaxKg {
            guard let cycleIndex = context.cycleIndex else {
                return (trainingMaxKg, context.stall.trainingMaxCycle)
            }
            let lastBumped = context.stall.trainingMaxCycle ?? cycleIndex
            guard cycleIndex > lastBumped else { return (trainingMaxKg, lastBumped) }
            let bumped = trainingMaxKg + context.trainingMaxIncrementKg
            guard let amrapE1RM = bestAMRAPE1RM(context) else { return (bumped, cycleIndex) }
            let cap = amrapE1RM * TrainingConstants.trainingMaxFraction
            return (max(trainingMaxKg, min(bumped, cap)), cycleIndex)
        }
        guard let e1rm = bestRecentE1RM(context) else { return nil }
        return (e1rm * TrainingConstants.trainingMaxFraction, context.cycleIndex)
    }

    /// Best e1RM across the last few non-deload sessions — the lifter's strength,
    /// not whatever the most recent (possibly high-rep or light) day happened to be.
    static func bestRecentE1RM(_ context: RuleContext, sessions: Int = 6) -> Double? {
        context.history.prefix(sessions).filter { !$0.wasPlannedDeload }
            .compactMap { bestE1RM($0.workingSets) }.max()
    }

    private static func bestAMRAPE1RM(_ context: RuleContext) -> Double? {
        let amrapSets = context.history.prefix(6).filter { !$0.wasPlannedDeload }
            .flatMap { $0.workingSets.filter { $0.kind == .amrap } }
        return bestE1RM(amrapSets)
    }
}
