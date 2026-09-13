import Foundation

extension ProgressionEngine {
    /// Bodyweight rule (plan.md §7): add reps up to a ceiling, then add a set
    /// (up to a max), then suggest a harder variation or added load. The set
    /// count is sized from the plan, not from however many sets were logged: a
    /// partial session holds, extra sets don't count.
    static func prescribeBodyweight(_ context: RuleContext, repCeiling: Int, maxSets: Int) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = context.baselineWorkingSets
        guard !workingSets.isEmpty else { return context.firstTimePrescribed() }
        let addedWeightKg = workingSets.first?.weightKg ?? 0
        let workingPlanned = context.planned.filter { $0.kind.countsTowardStats }
        let plannedCount = workingPlanned.isEmpty ? workingSets.count : workingPlanned.count

        if workingSets.count < plannedCount {
            let planReps = workingPlanned.first?.targetReps ?? workingSets.map(\.reps).max() ?? repCeiling
            return bodyweightResult(context, BodyweightOutcome(
                addedWeightKg: addedWeightKg, setCount: plannedCount, reps: planReps,
                reason: PrescriptionReason(
                    title: "Repeat \(plannedCount)×\(planReps)",
                    body: "Only \(workingSets.count) of \(plannedCount) sets were logged last session " +
                        "— same plan again.",
                    kind: .repeat
                ),
                baselineDate: baseline.date
            ))
        }

        let judged = Array(workingSets.prefix(plannedCount))
        let summary = performanceSummary(judged)
        if judged.allSatisfy({ $0.reps >= repCeiling }) {
            if plannedCount < maxSets {
                return bodyweightResult(context, BodyweightOutcome(
                    addedWeightKg: addedWeightKg, setCount: plannedCount + 1, reps: repCeiling,
                    reason: PrescriptionReason(
                        title: "+1 set", body: "You hit \(summary) — add another set.", kind: .increase
                    ),
                    baselineDate: baseline.date
                ))
            }
            return bodyweightResult(context, BodyweightOutcome(
                addedWeightKg: addedWeightKg, setCount: plannedCount, reps: repCeiling,
                reason: PrescriptionReason(
                    title: "Try a harder variation",
                    body: "You maxed out \(maxSets) sets of \(repCeiling) — add load or a harder variation.",
                    kind: .plan
                ),
                baselineDate: baseline.date
            ))
        }

        let weakestReps = judged.map(\.reps).min() ?? 0
        let nextReps = min(repCeiling, weakestReps + 1)
        return bodyweightResult(context, BodyweightOutcome(
            addedWeightKg: addedWeightKg, setCount: plannedCount, reps: nextReps,
            reason: PrescriptionReason(
                title: "\(nextReps) reps",
                body: "You hit \(summary) last session — aim for \(nextReps) this time.", kind: .increase
            ),
            baselineDate: baseline.date
        ))
    }

    private static func bodyweightResult(_ context: RuleContext, _ outcome: BodyweightOutcome) -> Prescribed {
        let sets = (0..<outcome.setCount).map { _ in
            Prescription(
                weightKg: outcome.addedWeightKg, reps: outcome.reps, durationSeconds: nil,
                previous: nil, reason: outcome.reason.title
            )
        }
        return Prescribed(
            sets: sets, reason: outcome.reason, stall: context.stall, trainingMaxKg: context.trainingMaxKg,
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
    var baselineDate: Date?
}
