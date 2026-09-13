import Foundation

extension ProgressionEngine {
    /// Linear rule (plan.md §7): all working sets hit their target reps (and RPE
    /// if tracked) → add weight. A rep miss repeats the weight; three misses in a
    /// row deload 10 % of the working weight (capped by 90 % of e1RM and by one
    /// increment down — always a real decrease). Reps hit but RPE over target is
    /// a hold, not a miss.
    static func prescribeLinear(_ context: RuleContext, incrementKg: Double) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = context.baselineWorkingSets
        guard let baselineWeight = workingSets.first?.weightKg, !workingSets.isEmpty else {
            return context.firstTimePrescribed()
        }

        let stall = resetIfWeightChanged(context.stall, currentWeightKg: baselineWeight)
        let summary = performanceSummary(workingSets)
        switch setsHitTarget(workingSets: workingSets, planned: context.planned) {
        case .noTargets:
            return context.holdPrescribed(
                weightKg: baselineWeight, title: "Repeat \(context.formatted(kg: baselineWeight))",
                body: "No rep target is set for this exercise, so the rule can't judge last session " +
                    "— add target reps to progress automatically.",
                baselineDate: baseline.date
            )
        case .rpeOver:
            return prescribedResult(
                context, weightKg: baselineWeight,
                reason: PrescriptionReason(
                    title: "Repeat \(context.formatted(kg: baselineWeight))",
                    body: "You hit \(summary) last session but over your RPE target — hold the weight.",
                    kind: .repeat
                ),
                stall: stall.advancing(misses: stall.consecutiveMisses, weightKg: baselineWeight),
                baselineDate: baseline.date
            )
        case .hit:
            guard incrementKg > 0 else {
                return context.holdPrescribed(
                    weightKg: baselineWeight, title: "Repeat \(context.formatted(kg: baselineWeight))",
                    body: "This rule has no increment set — add one to progress automatically.",
                    baselineDate: baseline.date
                )
            }
            let newWeight = context.increased(baselineWeight, by: incrementKg)
            return prescribedResult(
                context, weightKg: newWeight,
                reason: PrescriptionReason(
                    title: context.increaseTitle(from: baselineWeight, to: newWeight),
                    body: "You hit \(summary) last session.", kind: .increase
                ),
                stall: stall.advancing(misses: 0, weightKg: newWeight),
                baselineDate: baseline.date
            )
        case .missedReps:
            return linearMiss(context, baselineWeight: baselineWeight, incrementKg: incrementKg, stall: stall)
        }
    }

    private static func linearMiss(
        _ context: RuleContext, baselineWeight: Double, incrementKg: Double, stall: StallState
    ) -> Prescribed {
        let summary = performanceSummary(context.baselineWorkingSets)
        let baselineDate = context.baseline?.date
        let misses = stall.consecutiveMisses + 1
        if misses >= TrainingConstants.linearMissesBeforeDeload {
            guard let deloadTarget = linearDeloadTarget(
                context, baselineWeight: baselineWeight, incrementKg: incrementKg
            ) else {
                return context.lightestLoadPrescribed(
                    weightKg: baselineWeight, misses: misses, baselineDate: baselineDate
                )
            }
            return prescribedResult(
                context, weightKg: deloadTarget,
                reason: PrescriptionReason(
                    title: "Deload to \(context.formatted(kg: deloadTarget))",
                    body: "\(misses) sessions in a row missed (last: \(summary)) — time to back off.",
                    kind: .deload
                ),
                stall: stall.advancing(misses: 0, weightKg: deloadTarget),
                baselineDate: baselineDate
            )
        }
        return prescribedResult(
            context, weightKg: baselineWeight,
            reason: PrescriptionReason(
                title: "Repeat \(context.formatted(kg: baselineWeight))",
                body: "You missed (\(summary)) last session — same weight again.", kind: .repeat
            ),
            stall: stall.advancing(misses: misses, weightKg: baselineWeight),
            baselineDate: baselineDate
        )
    }

    /// 90 % of the stalled weight, rounded down; never above 90 % of e1RM and
    /// never less than one increment below the stalled weight — but never below the
    /// grid's lightest load under the stalled weight either. Nil when there is none.
    static func linearDeloadTarget(
        _ context: RuleContext, baselineWeight: Double, incrementKg: Double
    ) -> Double? {
        let fraction = TrainingConstants.linearDeloadFraction
        let byWeight = context.roundedDown(baselineWeight * fraction)
        let byE1RM = bestE1RM(context.baselineWorkingSets).map { context.roundedDown($0 * fraction) }
        let oneStepDown = context.roundedDown(baselineWeight - max(incrementKg, 0))
        return context.deloadClamped(min(byWeight, byE1RM ?? byWeight, oneStepDown), below: baselineWeight)
    }

    /// A weight change (outside this engine's own repeats/deloads) resets the miss streak.
    static func resetIfWeightChanged(_ stall: StallState, currentWeightKg: Double) -> StallState {
        guard let lastWeightKg = stall.lastWeightKg,
              !StallState.sameWeight(lastWeightKg, currentWeightKg) else { return stall }
        return stall.advancing(misses: 0, weightKg: currentWeightKg)
    }

    enum TargetCheck: Equatable {
        /// Every planned set was logged and met its reps (and RPE, when tracked).
        case hit
        /// Fewer sets than planned, or a set under its rep target.
        case missedReps
        /// Reps all hit, but a tracked set came in over its RPE target.
        case rpeOver
        /// No planned set carries a rep target — nothing to judge against.
        case noTargets
    }

    /// Judges a session against its planned sets: a partial session (fewer sets
    /// than planned) is a miss, and a plan with no rep targets can't be judged.
    static func setsHitTarget(workingSets: [HistorySet], planned: [PlannedSetSpec]) -> TargetCheck {
        let workingPlanned = planned.filter { $0.kind.countsTowardStats }
        guard !workingPlanned.isEmpty, workingPlanned.contains(where: { $0.targetReps != nil }) else {
            return .noTargets
        }
        guard workingSets.count >= workingPlanned.count else { return .missedReps }
        let pairs = Array(zip(workingSets, workingPlanned))
        let repsMissed = pairs.contains { set, spec in
            spec.targetReps.map { set.reps < $0 } ?? false
        }
        if repsMissed { return .missedReps }
        let rpeOver = pairs.contains { set, spec in
            guard let target = spec.targetRPE, let rpe = set.effort?.rpe else { return false }
            return rpe > target
        }
        return rpeOver ? .rpeOver : .hit
    }

    /// Kept for callers that want a plain yes/no: only `.hit` counts.
    static func allSetsHitTarget(workingSets: [HistorySet], planned: [PlannedSetSpec]) -> Bool {
        setsHitTarget(workingSets: workingSets, planned: planned) == .hit
    }

    /// Best e1RM across the sets, counting reps in reserve when an RPE was logged.
    static func bestE1RM(_ sets: [HistorySet]) -> Double? {
        sets.compactMap { set in
            if let effort = set.effort {
                return OneRepMax.estimate(weight: set.weightKg, reps: set.reps, repsInReserve: effort.rir)
            }
            return OneRepMax.estimate(weight: set.weightKg, reps: set.reps)
        }.max()
    }

    /// "3×8 at RPE 7" when every set matched; "8, 8, 6" when they didn't.
    static func performanceSummary(_ sets: [HistorySet]) -> String {
        guard let first = sets.first else { return "your sets" }
        let reps = sets.map(\.reps)
        let base = reps.allSatisfy { $0 == first.reps }
            ? "\(sets.count)×\(first.reps)"
            : reps.map(String.init).joined(separator: ", ")
        guard let rpe = first.effort?.rpe else { return base }
        return "\(base) at RPE \(rpe == rpe.rounded() ? String(Int(rpe)) : String(rpe))"
    }

    /// Fills every planned set at `weightKg`, carrying the reason and updated stall state through.
    static func prescribedResult(
        _ context: RuleContext, weightKg: Double, reason: PrescriptionReason, stall: StallState,
        baselineDate: Date?
    ) -> Prescribed {
        let sets = context.planned.map { spec in
            Prescription(
                weightKg: weightKg, reps: spec.targetReps ?? 0, durationSeconds: spec.targetSeconds,
                previous: nil, reason: reason.title
            )
        }
        return Prescribed(
            sets: sets, reason: reason, stall: stall, trainingMaxKg: context.trainingMaxKg,
            previousDate: baselineDate
        )
    }
}
