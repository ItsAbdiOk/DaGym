import Foundation
import Testing
@testable import GymCore

@Suite("Coach: recovery debt")
struct CoachRulesRecoveryTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    @Test("2 muscles at/above the 0.75 spent threshold fires")
    func fires() {
        let input = CoachInput(recoveryMap: [.chest: 0.9, .quads: 0.8, .hams: 0.3])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .recoveryDebt })
    }

    @Test("both muscles just under the spent threshold doesn't fire")
    func nearMissValueDoesNotFire() {
        let input = CoachInput(recoveryMap: [.chest: 0.74, .quads: 0.70])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .recoveryDebt })
    }

    @Test("only 1 muscle over the threshold (under the min-muscle count) doesn't fire")
    func nearMissCountDoesNotFire() {
        let input = CoachInput(recoveryMap: [.chest: 0.9])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .recoveryDebt })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let fingerprint = CoachCard.makeFingerprint(rule: .recoveryDebt, key: "chest,quads")
        let interaction = CoachInteraction(
            rule: .recoveryDebt, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(
            recoveryMap: [.chest: 0.9, .quads: 0.8], interactions: [interaction]
        )
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .recoveryDebt })
    }
}
