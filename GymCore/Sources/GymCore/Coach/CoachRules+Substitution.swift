import Foundation

/// Struggling-exercise rule: reuses `Substitutions.candidates` (via the neutral
/// `.strugglingWithExercise` reason) for the actual scoring — this rule only decides *which* lift
/// has earned a swap suggestion and turns the top candidate into a card.
extension CoachRules {
    static func strugglingExerciseCards(input: CoachInput, now: Date) -> [CoachCard] {
        let threshold = TrainingConstants.coachStrugglingConsecutiveFailures
        let struggling = input.lifts
            .filter { $0.consecutiveFailedSessions >= threshold && $0.substitutionCandidate != nil }
            .sorted { lhs, rhs in
                lhs.consecutiveFailedSessions == rhs.consecutiveFailedSessions
                    ? lhs.name < rhs.name
                    : lhs.consecutiveFailedSessions > rhs.consecutiveFailedSessions
            }
        guard let worst = struggling.first, let exercise = worst.substitutionCandidate else { return [] }

        let candidates = Substitutions.candidates(
            for: exercise, reason: .strugglingWithExercise, library: input.substitutionLibrary,
            available: input.availableEquipment, recoveryMap: input.recoveryMap
        )
        guard let best = candidates.first else { return [] }

        let evidence: [CoachEvidenceItem] = [
            .init("Sessions short of target in a row", .count(worst.consecutiveFailedSessions)),
            .init("Suggested swap", .text(best.candidate.name))
        ]
        return [CoachCard(
            rule: .strugglingExercise, severity: .notice, title: "\(worst.name) isn't going well",
            body: "\(worst.name) has come up short of its rep target "
                + "\(worst.consecutiveFailedSessions) sessions in a row — \(best.candidate.name) hits "
                + "the same muscles and might fit you better.",
            evidence: evidence,
            suggestedAction: .substituteExercise(
                exerciseName: worst.name, candidateID: best.candidate.id, candidateName: best.candidate.name
            ),
            distinguishingKey: worst.name, firedDate: now
        )]
    }
}
