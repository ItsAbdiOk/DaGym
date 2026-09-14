import Foundation

/// Stalled-lift rule: reads `StallState.consecutiveMisses`, which the progression engine already
/// maintains per lift (`SessionHistory.swift`) — no second stall detector. The suggested action
/// reuses `DeloadDetector.deloadPlan(sets:load:)` for the concrete numbers.
extension CoachRules {
    static func stalledLiftCards(input: CoachInput, now: Date) -> [CoachCard] {
        let threshold = TrainingConstants.coachStalledLiftMisses
        let stalled = input.lifts
            .filter { $0.stallState.consecutiveMisses >= threshold }
            .sorted { lhs, rhs in
                lhs.stallState.consecutiveMisses == rhs.stallState.consecutiveMisses
                    ? lhs.name < rhs.name
                    : lhs.stallState.consecutiveMisses > rhs.stallState.consecutiveMisses
            }
        guard let worst = stalled.first else { return [] }

        let weight = worst.stallState.lastWeightKg ?? worst.lastWorkingWeightKg
        let evidence: [CoachEvidenceItem] = [
            .init("Consecutive misses", .count(worst.stallState.consecutiveMisses)),
            .init("Weight", .weightKg(weight ?? 0))
        ]
        let action: CoachSuggestedAction = weight.map { stalledWeight in
            let plan = DeloadDetector.deloadPlan(sets: worst.lastWorkingSetCount ?? 3, load: stalledWeight)
            return .deloadExercise(exerciseName: worst.name, toWeightKg: plan.loadKg, sets: plan.sets)
        } ?? .none

        return [CoachCard(
            rule: .stalledLift, severity: .warning, title: "\(worst.name) has stalled",
            body: "\(worst.name) hasn't moved for \(worst.stallState.consecutiveMisses) sessions in a row.",
            evidence: evidence, suggestedAction: action, distinguishingKey: worst.name, firedDate: now
        )]
    }
}
