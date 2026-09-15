import Foundation

/// Stalled-lift rule: reads `StallState.consecutiveMisses`, which the progression engine already
/// maintains per lift (`SessionHistory.swift`) — no second stall detector. The suggested action's
/// number is `CoachRules.deloadLoad`, which rounds onto the lift's own `LoadGrid` so what the card
/// promises is a weight the lifter can actually load.
///
/// `stallState` must be the engine's *current* judgement of the newest logged session (what the
/// app computes when it starts a workout), not the persisted counter, which lags a session —
/// see `TrainingConstants.coachStalledLiftMisses`. Fed that, `consecutiveMisses` is literally
/// the number of sessions in a row missed at `lastWeightKg`, and the card says exactly that.
/// The threshold is the lift's own (`CoachLiftSnapshot.stalledLiftMisses`): one short of its
/// rule's reset, so a linear + AMRAP lift — whose counter never passes 1 — still gets a card.
extension CoachRules {
    /// The one lift this rule would card: the longest-stalled, ties broken by name so the choice
    /// is deterministic. Exposed so `CoachEngine` can tell the later rules which lift is already
    /// spoken for without having to read a name back out of a finished card.
    static func stalledLift(input: CoachInput) -> CoachLiftSnapshot? {
        input.lifts
            .filter { $0.isStalled && isStillAtStalledWeight($0) }
            .min { lhs, rhs in
                lhs.stallState.consecutiveMisses == rhs.stallState.consecutiveMisses
                    ? lhs.name < rhs.name
                    : lhs.stallState.consecutiveMisses > rhs.stallState.consecutiveMisses
            }
    }

    /// A streak belongs to the weight it was counted at. When the lifter has since moved to a
    /// different weight by hand, the engine's next judgement zeroes the streak
    /// (`ProgressionEngine.resetIfWeightChanged`); a card built from the old streak would
    /// name a "current" weight they are no longer on and suggest one they may already be at.
    private static func isStillAtStalledWeight(_ lift: CoachLiftSnapshot) -> Bool {
        guard let stalled = lift.stallState.lastWeightKg, let current = lift.lastWorkingWeightKg else {
            return true
        }
        return StallState.sameWeight(stalled, current)
    }

    static func stalledLiftCards(input: CoachInput, now: Date) -> [CoachCard] {
        guard let worst = stalledLift(input: input) else { return [] }

        let misses = worst.stallState.consecutiveMisses
        let weight = worst.stallState.lastWeightKg ?? worst.lastWorkingWeightKg
        let target = weight.flatMap { deloadLoad(for: worst, stalledWeightKg: $0) }

        var evidence: [CoachEvidenceItem] = [.init("Sessions without progress", .count(misses))]
        if let weight { evidence.append(.init("Current working weight", .weightKg(weight))) }
        if let target { evidence.append(.init("Suggested weight", .weightKg(target))) }

        let action: CoachSuggestedAction = target.map {
            .deloadExercise(exerciseName: worst.name, exerciseID: worst.exerciseID, toWeightKg: $0)
        } ?? .none

        return [CoachCard(
            rule: .stalledLift, severity: .warning, title: "\(worst.name) has stalled",
            body: body(name: worst.name, misses: misses, hasTarget: target != nil),
            evidence: evidence, suggestedAction: action, distinguishingKey: worst.name, firedDate: now
        )]
    }

    /// Two shapes, because a lift with nowhere lighter to go can't be told to back off — the
    /// same distinction `RuleContext.lightestLoadPrescribed` already draws in the engine.
    private static func body(name: String, misses: Int, hasTarget: Bool) -> String {
        let sessions = misses == 1 ? "session" : "sessions"
        let opening = "\(name) hasn't moved at the same weight for \(misses) \(sessions) in a row"
        guard hasTarget else {
            return opening + " — there's nothing lighter on this equipment, so a lighter "
                + "variation or fewer reps is the way forward."
        }
        return opening + ". Backing the weight off gives you a run-up at it again."
    }
}
