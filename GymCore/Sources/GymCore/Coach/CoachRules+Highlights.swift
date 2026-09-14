import Foundation

/// PR/milestone rule: surfaces `PersonalRecords`/`Milestones` results the app layer already
/// computed (`CoachPersonalRecordHighlight`/`CoachAchievementHighlight`) — this rule only filters
/// to what's still recent enough to be worth a card.
extension CoachRules {
    static func prMilestoneCards(input: CoachInput, now: Date) -> [CoachCard] {
        prCards(input: input, now: now) + achievementCards(input: input, now: now)
    }

    private static func prCards(input: CoachInput, now: Date) -> [CoachCard] {
        input.recentPRs.compactMap { highlight -> CoachCard? in
            guard isRecent(highlight.record.date, now: now) else { return nil }
            let evidence: [CoachEvidenceItem] = [
                .init("PR kind", .text(highlight.record.kind.rawValue)),
                .init("Value", .number(highlight.record.value)),
                .init("Date", .date(highlight.record.date))
            ]
            let key = "pr:\(highlight.exerciseName):\(highlight.record.kind.rawValue):"
                + dateKey(highlight.record.date)
            return CoachCard(
                rule: .prMilestone, severity: .info, title: "New PR: \(highlight.exerciseName)",
                body: PersonalRecords.formatLine(highlight.record), evidence: evidence,
                suggestedAction: .none, distinguishingKey: key, firedDate: now
            )
        }
    }

    private static func achievementCards(input: CoachInput, now: Date) -> [CoachCard] {
        input.recentAchievements.compactMap { highlight -> CoachCard? in
            guard isRecent(highlight.date, now: now) else { return nil }
            let title = "\(highlight.achievement.tier.displayName) tier: \(highlight.achievement.title)"
            let evidence: [CoachEvidenceItem] = [
                .init("Milestone", .text(highlight.achievement.title)),
                .init("Tier", .text(highlight.achievement.tier.displayName)),
                .init("Date", .date(highlight.date))
            ]
            let key = "milestone:\(highlight.achievement.id):\(highlight.achievement.tier.rawValue)"
            return CoachCard(
                rule: .prMilestone, severity: .info, title: title, body: highlight.achievement.line,
                evidence: evidence, suggestedAction: .none, distinguishingKey: key, firedDate: now
            )
        }
    }

    private static func isRecent(_ date: Date, now: Date) -> Bool {
        let ageDays = now.timeIntervalSince(date) / 86_400
        return ageDays >= 0 && ageDays <= TrainingConstants.coachHighlightLookbackDays
    }
}
