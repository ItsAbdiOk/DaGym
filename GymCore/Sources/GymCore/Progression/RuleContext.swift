import Foundation

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
    ///
    /// Callers must ask `oversizedRung` first: "the single step wins" is only safe while that
    /// step is a step. On a rack of 25s and 10s the step above 40 kg is 70, and this would
    /// hand back +75 % as if it were the capped answer.
    func increased(_ current: Double, by incrementKg: Double) -> Double {
        let oneStep = grid.nearestAbove(current)
        let candidate = rounded(current + incrementKg)
        let raised = candidate > current + 0.001 ? candidate : oneStep
        guard current > 0.001 else { return raised }
        let cap = roundedDown(current * (1 + TrainingConstants.maxSessionIncreaseFraction))
        return min(raised, max(oneStep, cap))
    }

    /// The next loadable rung above `current` when it is too big a jump to prescribe: past the
    /// `maxSessionIncreaseFraction` cap *and* more than `maxGridStepIncrements` of the rule's own
    /// increment away. Nil when `increased` can be trusted — including at the top of the rack,
    /// where there is no rung and `increased` already answers "repeat".
    func oversizedRung(above current: Double, by incrementKg: Double) -> Double? {
        guard current > 0.001, incrementKg > 0 else { return nil }
        let oneStep = grid.nearestAbove(current)
        let jump = oneStep - current
        guard jump > 0.001 else { return nil }
        let cap = roundedDown(current * (1 + TrainingConstants.maxSessionIncreaseFraction))
        guard oneStep > cap + 0.001 else { return nil }
        return jump > incrementKg * TrainingConstants.maxGridStepIncrements ? oneStep : nil
    }

    /// The hold for a hit whose next rung is oversized (`oversizedRung`): same weight, streak
    /// cleared (the session was a hit), and a reason that names the rung and the gap so the
    /// lifter knows it is the equipment, not the engine, saying stay.
    func oversizedRungHold(
        current: Double, rung: Double, summary: String, stall: StallState, baselineDate: Date?
    ) -> Prescribed {
        let jump = rung - current
        let percent = Int((jump / current * 100).rounded())
        let reason = PrescriptionReason(
            title: "Repeat \(formatted(kg: current))",
            body: "You hit \(summary) last session, but the next weight this equipment can load is "
                + "\(formatted(kg: rung)) — +\(formatted(kg: jump)), \(percent) % more — too big a jump for "
                + "one session. Add smaller plates, or repeat and add reps.",
            kind: .repeat
        )
        return ProgressionEngine.prescribedResult(
            self, weightKg: current, reason: reason,
            stall: stall.advancing(misses: 0, weightKg: current), baselineDate: baselineDate
        )
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
