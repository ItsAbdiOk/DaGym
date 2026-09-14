import Foundation
import Testing
@testable import GymCore

@Suite("Coach: recovery debt")
struct CoachRulesRecoveryTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    /// Enough logged sessions for the fatigue reference to mean something — below
    /// `coachRecoveryDebtMinSessions` the rule stays quiet whatever the map says.
    private func sessions(_ count: Int) -> [CoachSessionSummary] {
        (0..<count).map { index in
            CoachSessionSummary(
                date: CoachTestSupport.daysAgo(index + 1, from: now), plannedSetCount: 10,
                completedSetCount: 10, durationSeconds: 3600
            )
        }
    }

    private func input(
        map: [Muscle: Double], sessionCount: Int = 8, interactions: [CoachInteraction] = []
    ) -> CoachInput {
        CoachInput(
            recentSessions: sessions(sessionCount), recoveryMap: map, interactions: interactions
        )
    }

    @Test("2 muscles at/above the spent threshold fires")
    func fires() {
        let cards = CoachEngine.cards(
            for: input(map: [.chest: 0.7, .quads: 0.65, .hams: 0.3]), now: now, calendar: calendar
        )
        #expect(cards.contains { $0.rule == .recoveryDebt })
    }

    @Test("the card describes the training, not the body")
    func copyIsDescriptive() {
        let card = CoachEngine
            .cards(for: input(map: [.chest: 0.7, .quads: 0.65]), now: now, calendar: calendar)
            .first { $0.rule == .recoveryDebt }
        #expect(card?.body.contains("fatigue") == false)
        #expect(card?.title.contains("trained these hard") == true)
    }

    @Test("both muscles just under the spent threshold doesn't fire")
    func nearMissValueDoesNotFire() {
        let cards = CoachEngine.cards(
            for: input(map: [.chest: 0.59, .quads: 0.55]), now: now, calendar: calendar
        )
        #expect(!cards.contains { $0.rule == .recoveryDebt })
    }

    @Test("only 1 muscle over the threshold (under the min-muscle count) doesn't fire")
    func nearMissCountDoesNotFire() {
        let cards = CoachEngine.cards(for: input(map: [.chest: 0.9]), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .recoveryDebt })
    }

    @Test("a beginner's first few sessions never fire it, however spent the map reads")
    func tooLittleHistoryDoesNotFire() {
        let cards = CoachEngine.cards(
            for: input(map: [.chest: 0.95, .quads: 0.95], sessionCount: 3), now: now, calendar: calendar
        )
        #expect(!cards.contains { $0.rule == .recoveryDebt })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let fingerprint = CoachCard.makeFingerprint(rule: .recoveryDebt, key: "chest,quads")
        let interaction = CoachInteraction(
            rule: .recoveryDebt, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let cards = CoachEngine.cards(
            for: input(map: [.chest: 0.9, .quads: 0.8], interactions: [interaction]),
            now: now, calendar: calendar
        )
        #expect(!cards.contains { $0.rule == .recoveryDebt })
    }

    @Test("the fingerprint survives the spent scores decaying past each other overnight")
    func fingerprintIsStableWhileTheSameMusclesAreSpent() {
        let today = CoachEngine
            .cards(for: input(map: [.chest: 0.9, .quads: 0.8]), now: now, calendar: calendar)
        // Same two muscles, but chest has decayed below quads — the displayed order flips while
        // the problem is identical, and the old key embedded that order.
        let later = CoachEngine
            .cards(for: input(map: [.chest: 0.65, .quads: 0.7]), now: now, calendar: calendar)
        #expect(today.first { $0.rule == .recoveryDebt }?.fingerprint
            == later.first { $0.rule == .recoveryDebt }?.fingerprint)
    }
}
