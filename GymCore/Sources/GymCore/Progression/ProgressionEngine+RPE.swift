import Foundation

extension ProgressionEngine {
    /// RPE-based rule (plan.md §7): keep the reps/RPE targets fixed and
    /// recompute the load each session from the top set's implied e1RM — the
    /// working set with the highest RPE-adjusted e1RM, so a normal 7/8/9 fatigue
    /// ramp across straight sets doesn't ratchet the load down. No logged RPE →
    /// hold the weight (the rule has nothing to work from). Per-session change
    /// is clamped to ±`rpeMaxSessionChangeFraction`.
    static func prescribeRPEBased(_ context: RuleContext, targetRPE: Double) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = context.baselineWorkingSets
        guard let firstSet = workingSets.first else { return context.firstTimePrescribed() }
        let workingPlanned = context.planned.filter { $0.kind.countsTowardStats }

        let rated = workingSets.enumerated().compactMap { index, set -> RatedSet? in
            set.effort.map { RatedSet(index: index, set: set, rpe: $0.rpe) }
        }
        guard let top = rated.max(by: { $0.e1RM < $1.e1RM }) else {
            return context.holdPrescribed(
                weightKg: firstSet.weightKg, title: "Repeat \(context.formatted(kg: firstSet.weightKg))",
                body: "No RPE was logged last session — log an RPE to let this rule adjust the load.",
                baselineDate: baseline.date
            )
        }

        let spec = workingPlanned.indices.contains(top.index)
            ? workingPlanned[top.index] : workingPlanned.first
        let targetReps = spec?.targetReps ?? top.set.reps
        let setTargetRPE = spec?.targetRPE ?? targetRPE
        let raw = RPELoad.nextLoad(
            fromWeightKg: top.set.weightKg, reps: top.set.reps, rpe: top.rpe,
            targetReps: targetReps, targetRPE: setTargetRPE
        )
        let swing = TrainingConstants.rpeMaxSessionChangeFraction
        let clamped = min(max(raw, top.set.weightKg * (1 - swing)), top.set.weightKg * (1 + swing))
        let roundedWeight = clampedToGrid(context, clamped, previous: top.set.weightKg, swing: swing)

        let kind: PrescriptionReason.Kind = roundedWeight > top.set.weightKg + 0.001 ? .increase
            : roundedWeight < top.set.weightKg - 0.001 ? .deload : .repeat
        let sets = context.planned.map { spec in
            Prescription(
                weightKg: roundedWeight, reps: spec.targetReps ?? targetReps,
                durationSeconds: spec.targetSeconds, previous: nil,
                reason: "Recalculated for RPE \(rpeText(setTargetRPE))"
            )
        }
        return Prescribed(
            sets: sets,
            reason: PrescriptionReason(
                title: context.formatted(kg: roundedWeight),
                body: "Your top set was \(top.set.reps) at \(context.formatted(kg: top.set.weightKg)) " +
                    "@ RPE \(rpeText(top.rpe)) last session " +
                    "(working e1RM \(context.formatted(kg: top.e1RM))).",
                kind: kind
            ),
            stall: StallState(consecutiveMisses: 0, lastWeightKg: roundedWeight),
            trainingMaxKg: context.trainingMaxKg, previousDate: baseline.date
        )
    }

    /// Rounds onto the grid without letting the rounding itself push past the ±swing
    /// clamp (a 2.5 kg grid step on a 20 kg load is already 12.5 %): if the nearest
    /// grid weight lands outside the band, stay on the previous weight.
    private static func clampedToGrid(
        _ context: RuleContext, _ target: Double, previous: Double, swing: Double
    ) -> Double {
        let rounded = context.rounded(target)
        if rounded > previous * (1 + swing) + 0.001 || rounded < previous * (1 - swing) - 0.001 {
            return previous
        }
        return rounded
    }

    private struct RatedSet {
        var index: Int
        var set: HistorySet
        var rpe: Double

        /// The invertible Epley e1RM (`RPELoad`), not the PR banner's three-formula mean.
        var e1RM: Double { RPELoad.e1RM(weight: set.weightKg, reps: set.reps, rpe: rpe) }
    }

    private static func rpeText(_ rpe: Double) -> String {
        rpe == rpe.rounded() ? String(Int(rpe)) : String(rpe)
    }
}
