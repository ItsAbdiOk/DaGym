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
        // Keyed on the lifts driving the suggestion, not on the reason text — that text carries a
        // hard-week count that ticks up every Monday, so a dismissal used to expire on its own.
        let fingerprint = CoachCard.makeFingerprint(rule: .deloadOverdue, key: "Bench,Squat")
        let interaction = CoachInteraction(
            rule: .deloadOverdue, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(lifts: lifts, interactions: [interaction])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .deloadOverdue })
    }

    @Test("the fingerprint doesn't move when another hard week passes")
    func fingerprintIgnoresTheHardWeekCount() {
        let lifts = [lift(name: "Bench", misses: 3), lift(name: "Squat", misses: 4)]
        let thisWeek = CoachEngine.deloadCard(
            for: CoachInput(lifts: lifts, hardWeeksInARow: 5), now: now
        )
        let nextWeek = CoachEngine.deloadCard(
            for: CoachInput(lifts: lifts, hardWeeksInARow: 6),
            now: CoachTestSupport.daysFromNow(7, from: now)
        )
        #expect(thisWeek?.fingerprint == nextWeek?.fingerprint)
        // The reason text still reports the real count, it just isn't the identity.
        #expect(thisWeek?.body != nextWeek?.body)
    }

    @Test("one lift stalling doesn't earn both a stalled-lift card and a deload card")
    func collapsesIntoThePerLiftCard() {
        // A single lift with a genuine e1RM slide: DeloadDetector fires on the trend alone, and
        // the stalled-lift rule fires on the same lift. That is one problem, not two.
        let lift = CoachLiftSnapshot(
            name: "Squat", stallState: StallState(consecutiveMisses: 2, lastWeightKg: 100),
            e1rmTrend: [120, 115, 100], loadGrid: .step(2.5), lastWorkingWeightKg: 100
        )
        let cards = CoachEngine.cards(for: CoachInput(lifts: [lift]), now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .stalledLift })
        #expect(!cards.contains { $0.rule == .deloadOverdue })
        #expect(!cards.contains { $0.rule == .e1rmDowntrend })
    }

    @Test("accumulated hard weeks still earn their own card even when the lift is already carded")
    func hardWeeksAreNotCollapsed() {
        let lift = CoachLiftSnapshot(
            name: "Squat", stallState: StallState(consecutiveMisses: 2, lastWeightKg: 100),
            e1rmTrend: [120, 115, 100], loadGrid: .step(2.5), lastWorkingWeightKg: 100
        )
        let input = CoachInput(lifts: [lift], hardWeeksInARow: 6)
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .deloadOverdue })
    }
}
