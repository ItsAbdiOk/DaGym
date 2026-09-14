import Foundation

/// Deload-overdue rule: a thin wrapper around `DeloadDetector.evaluate`, which already combines
/// stalls, e1RM regression, rising RPE and hard-week count into one holistic call — this rule adds
/// nothing of its own beyond turning that suggestion into a card.
extension CoachRules {
    static func deloadOverdueCards(input: CoachInput, now: Date) -> [CoachCard] {
        let snapshots = input.lifts.map(\.deloadSnapshot)
        let suggestion = DeloadDetector.evaluate(lifts: snapshots, hardWeeks: input.hardWeeksInARow)
        guard let suggestion else {
            return []
        }
        let evidence: [CoachEvidenceItem] = [
            .init("Reason", .text(suggestion.reason)),
            .init("Hard weeks in a row", .count(input.hardWeeksInARow))
        ]
        return [CoachCard(
            rule: .deloadOverdue, severity: .warning, title: "A deload looks due",
            body: suggestion.reason, evidence: evidence, suggestedAction: .none,
            distinguishingKey: suggestion.fingerprint, firedDate: now
        )]
    }
}
