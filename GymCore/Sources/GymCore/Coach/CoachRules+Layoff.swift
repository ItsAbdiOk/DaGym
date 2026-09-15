import Foundation

/// Return-from-layoff rule: a plain gap check against `lastWorkoutDate` — the "reuse" here is the
/// suggested action's fraction, which the app layer applies to whatever weight the progression
/// engine would otherwise have picked, rather than this rule inventing its own load math.
///
/// The gap is counted in **calendar days** (`startOfDay` to `startOfDay`), not wall-clock
/// 24-hour blocks: a last workout on Monday evening seen on Sunday evening is six days to the
/// lifter, and the card's number should be the one they'd count.
extension CoachRules {
    static func returnFromLayoffCards(input: CoachInput, now: Date, calendar: Calendar) -> [CoachCard] {
        guard let last = input.lastWorkoutDate, last <= now else { return [] }
        let daysSince = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)
        ).day ?? 0
        guard daysSince >= TrainingConstants.coachLayoffMinDays else { return [] }

        let evidence: [CoachEvidenceItem] = [
            .init("Days since last workout", .count(daysSince)),
            .init("Last workout", .date(last))
        ]
        return [CoachCard(
            rule: .returnFromLayoff, severity: .notice, title: "Welcome back — ease in",
            body: "It's been \(daysSince) days since your last workout. Starting a bit lighter "
                + "helps you ramp back up without a setback.",
            evidence: evidence,
            suggestedAction: .easeBackIn(loadFraction: TrainingConstants.coachLayoffEaseBackFraction),
            distinguishingKey: dateKey(last), firedDate: now
        )]
    }
}
