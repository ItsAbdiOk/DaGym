import Foundation

/// Return-from-layoff rule: a plain gap check against `lastWorkoutDate` — the "reuse" here is the
/// suggested action's fraction, which the app layer applies to whatever weight the progression
/// engine would otherwise have picked, rather than this rule inventing its own load math.
extension CoachRules {
    static func returnFromLayoffCards(input: CoachInput, now: Date) -> [CoachCard] {
        guard let last = input.lastWorkoutDate, last <= now else { return [] }
        let daysSince = now.timeIntervalSince(last) / 86_400
        guard daysSince >= TrainingConstants.coachLayoffMinDays else { return [] }

        let evidence: [CoachEvidenceItem] = [
            .init("Days since last workout", .count(Int(daysSince))),
            .init("Last workout", .date(last))
        ]
        return [CoachCard(
            rule: .returnFromLayoff, severity: .notice, title: "Welcome back — ease in",
            body: "It's been \(Int(daysSince)) days since your last workout. Starting a bit lighter "
                + "helps you ramp back up without a setback.",
            evidence: evidence,
            suggestedAction: .easeBackIn(loadFraction: TrainingConstants.coachLayoffEaseBackFraction),
            distinguishingKey: dateKey(last), firedDate: now
        )]
    }
}
