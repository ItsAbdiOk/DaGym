import Foundation
import Testing
@testable import GymCore

@Suite("Coach: return from layoff")
struct CoachRulesLayoffTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    @Test("11 days since the last workout (past the 10-day floor) fires")
    func fires() {
        let last = CoachTestSupport.daysAgo(11, from: now)
        let cards = CoachEngine.cards(for: CoachInput(lastWorkoutDate: last), now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .returnFromLayoff })
    }

    @Test("9 days since the last workout (just under the floor) doesn't fire")
    func nearMissDoesNotFire() {
        let last = CoachTestSupport.daysAgo(9, from: now)
        let cards = CoachEngine.cards(for: CoachInput(lastWorkoutDate: last), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .returnFromLayoff })
    }

    @Test("no logged workout at all doesn't fire")
    func noHistoryDoesNotFire() {
        let cards = CoachEngine.cards(for: CoachInput(lastWorkoutDate: nil), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .returnFromLayoff })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let last = CoachTestSupport.daysAgo(11, from: now)
        let key = String(Int(last.timeIntervalSince1970))
        let fingerprint = CoachCard.makeFingerprint(rule: .returnFromLayoff, key: key)
        let interaction = CoachInteraction(
            rule: .returnFromLayoff, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(lastWorkoutDate: last, interactions: [interaction])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .returnFromLayoff })
    }
}
