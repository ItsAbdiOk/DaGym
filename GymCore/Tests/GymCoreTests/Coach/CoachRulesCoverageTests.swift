import Foundation
import Testing
@testable import GymCore

@Suite("Coach: muscle coverage gap")
struct CoachRulesCoverageTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    private func input(hamsSets: Double, interactions: [CoachInteraction] = []) -> CoachInput {
        CoachInput(
            muscleSetsInWindow: [.chest: 10, .quads: 8, .hams: hamsSets],
            trackedMuscles: [.chest, .quads, .hams], interactions: interactions
        )
    }

    @Test("a muscle under the 4-set floor fires")
    func fires() {
        let cards = CoachEngine.cards(for: input(hamsSets: 1), now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .muscleCoverageGap })
    }

    @Test("exactly at the floor doesn't fire")
    func nearMissDoesNotFire() {
        let cards = CoachEngine.cards(for: input(hamsSets: 4), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .muscleCoverageGap })
    }

    @Test("empty tracked-muscle list never fires")
    func emptyTrackedMusclesDoesNotFire() {
        let input = CoachInput(muscleSetsInWindow: [.chest: 0], trackedMuscles: [])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .muscleCoverageGap })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let fingerprint = CoachCard.makeFingerprint(rule: .muscleCoverageGap, key: Muscle.hams.rawValue)
        let interaction = CoachInteraction(
            rule: .muscleCoverageGap, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let cards = CoachEngine.cards(
            for: input(hamsSets: 1, interactions: [interaction]), now: now, calendar: calendar
        )
        #expect(!cards.contains { $0.rule == .muscleCoverageGap })
    }
}
