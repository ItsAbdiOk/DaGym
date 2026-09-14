import Foundation
import Testing
@testable import GymCore

@Suite("Coach: PR / milestone highlights")
struct CoachRulesHighlightsTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    private func pr(daysAgo: Int) -> CoachPersonalRecordHighlight {
        CoachPersonalRecordHighlight(
            exerciseName: "Deadlift",
            record: PersonalRecord(
                kind: .e1rm, value: 180, weightKg: 150, reps: 3,
                date: CoachTestSupport.daysAgo(daysAgo, from: now)
            )
        )
    }

    @Test("a PR from yesterday (within the 3-day lookback) fires")
    func fires() {
        let input = CoachInput(recentPRs: [pr(daysAgo: 1)])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .prMilestone })
    }

    @Test("a PR from 4 days ago (just past the lookback) doesn't fire")
    func nearMissDoesNotFire() {
        let input = CoachInput(recentPRs: [pr(daysAgo: 4)])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .prMilestone })
    }

    @Test("a milestone tier earned yesterday fires")
    func achievementFires() {
        let milestone = Achievement(
            id: "workoutCount", tier: .bronze, title: "Workout Count", line: "10 logged"
        )
        let achievement = CoachAchievementHighlight(
            achievement: milestone, date: CoachTestSupport.daysAgo(1, from: now)
        )
        let input = CoachInput(recentAchievements: [achievement])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .prMilestone })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let highlight = pr(daysAgo: 1)
        let key = "pr:\(highlight.exerciseName):\(highlight.record.kind.rawValue):"
            + String(Int(highlight.record.date.timeIntervalSince1970))
        let fingerprint = CoachCard.makeFingerprint(rule: .prMilestone, key: key)
        let interaction = CoachInteraction(
            rule: .prMilestone, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(recentPRs: [highlight], interactions: [interaction])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .prMilestone })
    }
}
