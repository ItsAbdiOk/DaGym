import Foundation
import Testing
@testable import GymCore

@Suite("Coach: deload overdue")
struct CoachRulesDeloadTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    private func lift(name: String, misses: Int) -> CoachLiftSnapshot {
        CoachLiftSnapshot(name: name, stallState: StallState(consecutiveMisses: misses), e1rmTrend: [100])
    }

    @Test("2 lifts stalled 3+ sessions in a row fires, wrapping DeloadDetector's own suggestion")
    func fires() {
        let lifts = [lift(name: "Bench", misses: 3), lift(name: "Squat", misses: 4)]
        let cards = CoachEngine.cards(for: CoachInput(lifts: lifts), now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .deloadOverdue })
    }

    @Test("only one lift stalling (DeloadDetector's own near-miss) doesn't fire")
    func nearMissDoesNotFire() {
        let lifts = [lift(name: "Bench", misses: 5), lift(name: "Squat", misses: 0)]
        let cards = CoachEngine.cards(for: CoachInput(lifts: lifts), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .deloadOverdue })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let lifts = [lift(name: "Bench", misses: 3), lift(name: "Squat", misses: 4)]
        let snapshots = lifts.map(\.deloadSnapshot)
        guard let suggestion = DeloadDetector.evaluate(lifts: snapshots, hardWeeks: 0) else {
            Issue.record("expected DeloadDetector to fire for the fixture")
            return
        }
        let fingerprint = CoachCard.makeFingerprint(rule: .deloadOverdue, key: suggestion.fingerprint)
        let interaction = CoachInteraction(
            rule: .deloadOverdue, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(lifts: lifts, interactions: [interaction])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .deloadOverdue })
    }
}
