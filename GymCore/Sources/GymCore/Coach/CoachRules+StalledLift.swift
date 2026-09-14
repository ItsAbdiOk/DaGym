import Foundation

/// Stalled-lift rule: reads `StallState.consecutiveMisses`, which the progression engine already
/// maintains per lift (`SessionHistory.swift`) — no second stall detector. The suggested action's
/// number is `CoachRules.deloadLoad`, which rounds onto the lift's own `LoadGrid` so what the card
/// promises is a weight the lifter can actually load.
///
/// Fires at `TrainingConstants.coachStalledLiftMisses`, not at the engine's own deload count —
/// see that constant for the one-session lag that makes 3 unreachable and 2 redundant.
extension CoachRules {
    /// The one lift this rule would card: the longest-stalled, ties broken by name so the choice
    /// is deterministic. Exposed so `CoachEngine` can tell the later rules which lift is already
    /// spoken for without having to read a name back out of a finished card.
    static func stalledLift(input: CoachInput) -> CoachLiftSnapshot? {
        let threshold = TrainingConstants.coachStalledLiftMisses
        return input.lifts
            .filter { $0.stallState.consecutiveMisses >= threshold }
            .min { lhs, rhs in
                lhs.stallState.consecutiveMisses == rhs.stallState.consecutiveMisses
                    ? lhs.name < rhs.name
                    : lhs.stallState.consecutiveMisses > rhs.stallState.consecutiveMisses
            }
    }

    static func stalledLiftCards(input: CoachInput, now: Date) -> [CoachCard] {
        guard let worst = stalledLift(input: input) else { return [] }

        let misses = worst.stallState.consecutiveMisses
        let weight = worst.stallState.lastWeightKg ?? worst.lastWorkingWeightKg
        let target = weight.flatMap { deloadLoad(for: worst, stalledWeightKg: $0) }

        var evidence: [CoachEvidenceItem] = [.init("Sessions without progress", .count(misses + 1))]
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
        // `misses` is the persisted counter, which lags a session behind: the newest logged
        // session hasn't been judged when it is written. Report what actually happened.
        let sessions = misses + 1
        let opening = "\(name) hasn't moved at the same weight for \(sessions) sessions in a row"
        guard hasTarget else {
            return opening + " — there's nothing lighter on this equipment, so a lighter "
                + "variation or fewer reps is the way forward."
        }
        return opening + ". Backing the weight off gives you a run-up at it again."
    }
}
