import Foundation

extension ProgressionEngine {
    /// Assisted rule (plan.md §7): reduce assistance by one step once every
    /// working set hits its target reps, never below the floor. A partial session
    /// is a miss. Hitting the target at the floor hands off — "try it unassisted".
    /// `Prescription.assistanceKg` carries the assistance (and `weightKg` mirrors it
    /// for older callers).
    static func prescribeAssisted(_ context: RuleContext, stepKg: Double) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = context.baselineWorkingSets
        guard !workingSets.isEmpty else { return context.firstTimePrescribed() }
        // `weightKg` mirrors the assistance for this rule and is the field the log screen
        // actually writes, so a lifter who retypes the weight has said what the assistance
        // really was. `assistanceKg` is only trusted when there is no mirrored weight at all
        // (an import, or a row logged before the mirror existed) — read first, it went stale
        // the moment the number on the row was edited, and the rule then stepped down from a
        // weight the lifter never used.
        let logged = workingSets.first
        let assistanceKg = (logged?.weightKg ?? 0) > 0 ? (logged?.weightKg ?? 0) : (logged?.assistanceKg ?? 0)
        let summary = performanceSummary(workingSets)
        let check = setsHitTarget(workingSets: workingSets, planned: context.planned)
        let hit = check == .hit || check == .rpeOver

        let floor = TrainingConstants.assistedFloorKg
        let reason: PrescriptionReason
        let newAssistance: Double
        if hit, assistanceKg <= floor + 0.001 {
            newAssistance = floor
            reason = PrescriptionReason(
                title: "Try it unassisted",
                body: "You hit \(summary) with no assistance — switch this exercise to the bodyweight rule.",
                kind: .plan
            )
        } else if hit {
            newAssistance = max(floor, assistanceKg - stepKg)
            reason = PrescriptionReason(
                title: "−\(context.formatted(kg: assistanceKg - newAssistance)) assist",
                body: "You hit \(summary) last session.", kind: .increase
            )
        } else {
            newAssistance = assistanceKg
            reason = PrescriptionReason(
                title: "Repeat \(context.formatted(kg: assistanceKg)) assist",
                body: check == .noTargets
                    ? "No rep target is set for this exercise — add target reps to progress automatically."
                    : "You missed (\(summary)) last session.",
                kind: .repeat
            )
        }
        let sets = context.planned.map { spec in
            Prescription(
                weightKg: newAssistance, reps: spec.targetReps ?? 0, durationSeconds: spec.targetSeconds,
                previous: nil, reason: reason.title, assistanceKg: newAssistance
            )
        }
        return Prescribed(
            sets: sets, reason: reason, stall: context.stall, trainingMaxKg: context.trainingMaxKg,
            previousDate: baseline.date
        )
    }

    /// Timed rule (plan.md §7): add seconds to the hold once every set hits the
    /// hold it was asked for — `stall.lastTargetSeconds` when the engine set it,
    /// else the plan's target — so a 45 s hold when 60 s was prescribed is a
    /// miss even though the routine still says 30 s. A plan edited since the
    /// engine last set a target outranks that memory. Past `timedCeilingSeconds`
    /// the rule stops adding time and suggests load or a harder variation. Three
    /// short holds in a row back the ask off to 90 %, rounded down to 5 s.
    static func prescribeTimed(_ context: RuleContext, stepSeconds: Int) -> Prescribed {
        guard let baseline = context.baseline else { return context.firstTimePrescribed() }
        let workingSets = context.baselineWorkingSets
        guard let durationSeconds = workingSets.first?.durationSeconds, !workingSets.isEmpty else {
            return context.firstTimePrescribed()
        }
        let planTarget = context.planned.first { $0.kind.countsTowardStats }?.targetSeconds
        let seenPlanTarget = context.stall.lastPlanTargetSeconds
        let planEdited = planTarget != nil && seenPlanTarget != nil && planTarget != seenPlanTarget
        let remembered = planEdited ? nil : context.stall.lastTargetSeconds
        let askedSeconds = remembered ?? planTarget ?? durationSeconds
        let hit = workingSets.allSatisfy { ($0.durationSeconds ?? 0) >= askedSeconds }
        let ceiling = TrainingConstants.timedCeilingSeconds
        let loadKg = workingSets.first?.weightKg ?? 0

        let misses = hit ? 0 : context.stall.consecutiveMisses + 1
        let backedOff = timedBackoff(askedSeconds: askedSeconds, stepSeconds: stepSeconds)
        let reason: PrescriptionReason
        let newDuration: Int
        if hit, askedSeconds >= ceiling {
            newDuration = askedSeconds
            reason = PrescriptionReason(
                title: "Add load or go harder",
                body: "You're holding \(askedSeconds)s — add weight or a harder variation instead of " +
                    "more time.",
                kind: .plan
            )
        } else if hit {
            newDuration = max(askedSeconds, durationSeconds) + stepSeconds
            reason = PrescriptionReason(
                title: "+\(stepSeconds)s", body: "You held \(durationSeconds)s last session.", kind: .increase
            )
        } else if misses >= TrainingConstants.linearMissesBeforeDeload, let backedOff {
            newDuration = backedOff
            reason = PrescriptionReason(
                title: "Back off to \(backedOff)s",
                body: "\(misses) sessions in a row short of \(askedSeconds)s (last: \(durationSeconds)s) " +
                    "— shorten the hold and rebuild.",
                kind: .deload
            )
        } else {
            newDuration = askedSeconds
            reason = PrescriptionReason(
                title: "Repeat \(askedSeconds)s",
                body: "You held \(durationSeconds)s of the \(askedSeconds)s hold last session.", kind: .repeat
            )
        }
        let sets = context.planned.map { spec in
            Prescription(
                weightKg: loadKg, reps: spec.targetReps ?? 0, durationSeconds: newDuration,
                previous: nil, reason: reason.title
            )
        }
        var stall = context.stall
        stall.lastTargetSeconds = newDuration
        stall.lastPlanTargetSeconds = planTarget
        stall.consecutiveMisses = reason.kind == .deload ? 0 : misses
        return Prescribed(
            sets: sets, reason: reason, stall: stall, trainingMaxKg: context.trainingMaxKg,
            previousDate: baseline.date
        )
    }

    /// 90 % of the asked hold rounded down to 5 s, never under one step and always
    /// shorter than what was asked; nil when the ask is already as short as it can be.
    static func timedBackoff(askedSeconds: Int, stepSeconds: Int) -> Int? {
        let rounding = TrainingConstants.timedRoundingSeconds
        let fraction = TrainingConstants.timedBackoffFraction
        let rounded = Int((Double(askedSeconds) * fraction / Double(rounding)).rounded(.down)) * rounding
        let backedOff = max(max(stepSeconds, 1), rounded)
        return backedOff < askedSeconds ? backedOff : nil
    }
}
