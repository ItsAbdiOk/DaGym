import Foundation
import Testing
@testable import GymCore

@Suite("Coach: session drift")
struct CoachRulesDriftTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")

    /// 8 baseline sessions (oldest) at full set completion and an hour long, followed by 4 recent
    /// sessions at `recentCompletedSets`/10 planned sets — the shape `sessionDriftCards` compares.
    private func sessions(
        recentCompletedSets: Int, recentDurationSeconds: Int = 3600
    ) -> [CoachSessionSummary] {
        var sessions: [CoachSessionSummary] = []
        for day in stride(from: 12, through: 5, by: -1) {
            sessions.append(CoachSessionSummary(
                date: CoachTestSupport.daysAgo(day, from: now),
                plannedSetCount: 10, completedSetCount: 10, durationSeconds: 3600
            ))
        }
        for day in stride(from: 4, through: 1, by: -1) {
            sessions.append(CoachSessionSummary(
                date: CoachTestSupport.daysAgo(day, from: now),
                plannedSetCount: 10, completedSetCount: recentCompletedSets,
                durationSeconds: recentDurationSeconds
            ))
        }
        return sessions
    }

    @Test("recent sessions completing half their sets vs a full baseline fires")
    func fires() {
        let input = CoachInput(recentSessions: sessions(recentCompletedSets: 5))
        let cards = CoachEngine.cards(for: input, now: now, calendar: CoachTestSupport.calendar)
        #expect(cards.contains { $0.rule == .sessionDrift })
    }

    @Test("an 80% completion rate (20% drop) stays under the 25% threshold and doesn't fire")
    func nearMissDoesNotFire() {
        let input = CoachInput(recentSessions: sessions(recentCompletedSets: 8))
        let cards = CoachEngine.cards(for: input, now: now, calendar: CoachTestSupport.calendar)
        #expect(!cards.contains { $0.rule == .sessionDrift })
    }

    @Test("fewer than the combined lookback + baseline session count never fires")
    func tooFewSessionsDoesNotFire() {
        let input = CoachInput(recentSessions: Array(sessions(recentCompletedSets: 2).suffix(6)))
        let cards = CoachEngine.cards(for: input, now: now, calendar: CoachTestSupport.calendar)
        #expect(!cards.contains { $0.rule == .sessionDrift })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let sessionList = sessions(recentCompletedSets: 5)
        guard let mostRecentDate = sessionList.max(by: { $0.date < $1.date })?.date else {
            Issue.record("expected at least one session")
            return
        }
        // Keyed on the week the newest session falls in, not its timestamp: drift is a
        // weeks-long shape, and a per-session key minted a fresh fingerprint every workout.
        let calendar = CoachTestSupport.calendar
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: mostRecentDate)?.start ?? mostRecentDate
        let key = DateKey.string(for: weekStart, calendar: calendar)
        let fingerprint = CoachCard.makeFingerprint(rule: .sessionDrift, key: key)
        let interaction = CoachInteraction(
            rule: .sessionDrift, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(recentSessions: sessionList, interactions: [interaction])
        let cards = CoachEngine.cards(for: input, now: now, calendar: CoachTestSupport.calendar)
        #expect(!cards.contains { $0.rule == .sessionDrift })
    }

    @Test("sessions with no plan behind them carry no set signal")
    func unplannedSessionsAreNotBaseline() {
        // Every baseline session freestyle (`plannedSetCount == 0`, what the store now reports
        // for a session with no routine). There is no plan to have drifted from, so a collapsed
        // recent set count must not fire on its own — only duration could, and it hasn't moved.
        var sessionList = sessions(recentCompletedSets: 3)
        for index in 0..<8 {
            sessionList[index] = CoachSessionSummary(
                date: sessionList[index].date, plannedSetCount: 0, completedSetCount: 14,
                durationSeconds: 3600
            )
        }
        let input = CoachInput(recentSessions: sessionList)
        let cards = CoachEngine.cards(for: input, now: now, calendar: CoachTestSupport.calendar)
        #expect(!cards.contains { $0.rule == .sessionDrift })
    }

    @Test("a workout left open overnight is ignored rather than inflating the baseline")
    func overnightSessionIsNotABaseline() {
        // Baseline sets and recent sets are identical, so only duration can fire this. One
        // 14-hour "session" in the baseline would make every normal session afterwards look like
        // a 75 % collapse.
        var sessionList = sessions(recentCompletedSets: 10)
        sessionList[0] = CoachSessionSummary(
            date: sessionList[0].date, plannedSetCount: 10, completedSetCount: 10,
            durationSeconds: 14 * 3600
        )
        let input = CoachInput(recentSessions: sessionList)
        let cards = CoachEngine.cards(for: input, now: now, calendar: CoachTestSupport.calendar)
        #expect(!cards.contains { $0.rule == .sessionDrift })
    }
}
