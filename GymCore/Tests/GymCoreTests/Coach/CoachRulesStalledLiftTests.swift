import Foundation
import Testing
@testable import GymCore

@Suite("Coach: stalled lift")
struct CoachRulesStalledLiftTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    private func lift(misses: Int) -> CoachLiftSnapshot {
        CoachLiftSnapshot(
            name: "Bench Press",
            stallState: StallState(consecutiveMisses: misses, lastWeightKg: 60),
            e1rmTrend: [], lastWorkingWeightKg: 60, lastWorkingSetCount: 4
        )
    }

    @Test("3 consecutive misses at the same weight fires")
    func fires() {
        let cards = CoachEngine.cards(for: CoachInput(lifts: [lift(misses: 3)]), now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .stalledLift })
        let card = cards.first { $0.rule == .stalledLift }
        guard case .deloadExercise(let name, _, _) = card?.suggestedAction else {
            Issue.record("expected a deload suggestion")
            return
        }
        #expect(name == "Bench Press")
    }

    @Test("2 consecutive misses (just under the threshold) doesn't fire")
    func nearMissDoesNotFire() {
        let cards = CoachEngine.cards(for: CoachInput(lifts: [lift(misses: 2)]), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .stalledLift })
    }

    @Test("no lifts never fires")
    func noLiftsDoesNotFire() {
        let cards = CoachEngine.cards(for: CoachInput(lifts: []), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .stalledLift })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let fingerprint = CoachCard.makeFingerprint(rule: .stalledLift, key: "Bench Press")
        let interaction = CoachInteraction(
            rule: .stalledLift, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(lifts: [lift(misses: 3)], interactions: [interaction])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .stalledLift })
    }
}
