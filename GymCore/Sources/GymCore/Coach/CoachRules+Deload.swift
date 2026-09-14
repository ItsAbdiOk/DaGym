import Foundation

/// Deload-overdue rule: a thin wrapper around `DeloadDetector.evaluate`, which already combines
/// stalls, e1RM regression, rising RPE and hard-week count into one holistic call — this rule adds
/// nothing of its own beyond turning that suggestion into a card, deciding when that suggestion is
/// just a per-lift card said again, and giving it a fingerprint that survives a week passing.
extension CoachRules {
    /// - Parameter coveredLifts: lifts that already have their own card this pass. When the
    ///   suggestion is driven *only* by those lifts and the hard-week arm isn't involved, this
    ///   card says nothing new — one problem, one card.
    static func deloadOverdueCards(
        input: CoachInput, now: Date, coveredLifts: Set<String>
    ) -> [CoachCard] {
        let snapshots = input.lifts.map(\.deloadSnapshot)
        guard let suggestion = DeloadDetector.evaluate(
            lifts: snapshots, hardWeeks: input.hardWeeksInARow
        ) else {
            return []
        }
        let driving = Set(input.lifts.filter(\.drivesDeloadSuggestion).map(\.name))
        let hardWeeksInvolved = input.hardWeeksInARow >= TrainingConstants.deloadHardWeeksThreshold
        if !hardWeeksInvolved, !driving.isEmpty, driving.isSubset(of: coveredLifts) { return [] }

        let evidence: [CoachEvidenceItem] = [
            .init("Reason", .text(suggestion.reason)),
            .init("Hard weeks in a row", .count(input.hardWeeksInARow))
        ]
        return [CoachCard(
            rule: .deloadOverdue, severity: .warning, title: "A deload looks due",
            body: suggestion.reason, evidence: evidence, suggestedAction: .none,
            distinguishingKey: distinguishingKey(driving: driving, hardWeeksInvolved: hardWeeksInvolved),
            firedDate: now
        )]
    }

    /// Which lifts are behind the suggestion, plus whether accumulated hard weeks are part of it
    /// — deliberately *not* `DeloadSuggestion.fingerprint`, which hashes the reason text. That
    /// text contains "5 hard weeks in a row without a lighter week", so it changed every Monday
    /// and a dismissal never lasted its own cooldown. A lift joining or leaving the set, or the
    /// hard-week arm engaging, is a different problem and still produces a different key.
    private static func distinguishingKey(driving: Set<String>, hardWeeksInvolved: Bool) -> String {
        let lifts = driving.sorted().joined(separator: ",")
        return hardWeeksInvolved ? "hardweeks|\(lifts)" : lifts
    }
}
