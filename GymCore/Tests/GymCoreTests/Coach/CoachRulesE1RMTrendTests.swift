import Foundation
import Testing
@testable import GymCore

@Suite("Coach: e1RM downtrend")
struct CoachRulesE1RMTrendTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    private func lift(trend: [Double]) -> CoachLiftSnapshot {
        CoachLiftSnapshot(name: "Squat", stallState: StallState(), e1rmTrend: trend)
    }

    @Test("a monotone 10% decline over 4 sessions fires")
    func fires() {
        let input = CoachInput(lifts: [lift(trend: [100, 100, 95, 90])])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .e1rmDowntrend })
    }

    @Test("a 4% decline stays under the 5% threshold and doesn't fire")
    func nearMissDoesNotFire() {
        let input = CoachInput(lifts: [lift(trend: [100, 100, 100, 96])])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .e1rmDowntrend })
    }

    @Test("a big drop that then partially recovers isn't a monotone trend and doesn't fire")
    func nonMonotonicDoesNotFire() {
        let input = CoachInput(lifts: [lift(trend: [100, 80, 100, 90])])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .e1rmDowntrend })
    }

    @Test("fewer than the window's session count never fires")
    func tooFewSessionsDoesNotFire() {
        let input = CoachInput(lifts: [lift(trend: [100, 90, 80])])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .e1rmDowntrend })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let fingerprint = CoachCard.makeFingerprint(rule: .e1rmDowntrend, key: "Squat")
        let interaction = CoachInteraction(
            rule: .e1rmDowntrend, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(lifts: [lift(trend: [100, 100, 95, 90])], interactions: [interaction])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .e1rmDowntrend })
    }
}
