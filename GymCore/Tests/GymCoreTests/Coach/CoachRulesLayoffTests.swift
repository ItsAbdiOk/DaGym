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

    @Test("the gap is counted in calendar days, not 24-hour blocks")
    func gapIsCalendarDays() {
        // Last workout Monday 20:00, now the second Sunday after at 19:00: 13 calendar days, but
        // only 12.96 wall-clock days — the lifter counts 13.
        let last = CoachTestSupport.date("2024-01-01T20:00:00Z")
        let sundayEvening = CoachTestSupport.date("2024-01-14T19:00:00Z")
        let input = CoachInput(lastWorkoutDate: last)
        let cards = CoachEngine.cards(for: input, now: sundayEvening, calendar: calendar)
        let card = cards.first { $0.rule == .returnFromLayoff }
        #expect(card?.body.contains("13 days") == true)
        #expect(card?.evidence.first?.value == .count(13))

        // 9.9 wall-clock days but 10 calendar days: the floor is crossed on the calendar.
        let tenCalendarDays = CoachTestSupport.date("2024-01-11T18:00:00Z")
        let fires = CoachEngine.cards(for: input, now: tenCalendarDays, calendar: calendar)
        #expect(fires.contains { $0.rule == .returnFromLayoff })
    }
}
