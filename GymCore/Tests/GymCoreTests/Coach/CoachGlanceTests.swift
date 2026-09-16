import Foundation
import Testing
@testable import GymCore

@Suite("CoachGlance: next planned session and the Coach says line")
struct CoachGlanceTests {
    private let calendar = CoachTestSupport.calendar
    // Wednesday.
    private let now = CoachTestSupport.date("2026-09-16T10:00:00Z")

    @Test("the day label reads Today, Tomorrow, then the short weekday")
    func dayLabels() {
        let today = CoachTestSupport.date("2026-09-16T18:00:00Z")
        let tomorrow = CoachTestSupport.date("2026-09-17T06:00:00Z")
        let friday = CoachTestSupport.date("2026-09-18T18:00:00Z")
        let nextWednesday = CoachTestSupport.date("2026-09-23T18:00:00Z")

        #expect(NextPlannedSession.dayLabel(for: today, now: now, calendar: calendar) == "Today")
        #expect(NextPlannedSession.dayLabel(for: tomorrow, now: now, calendar: calendar) == "Tomorrow")
        #expect(NextPlannedSession.dayLabel(for: friday, now: now, calendar: calendar) == "Fri")
        #expect(NextPlannedSession.dayLabel(for: nextWednesday, now: now, calendar: calendar) == "Wed")
    }

    @Test("the detail line joins the day and the duration")
    func detailLine() {
        let session = NextPlannedSession(
            routineName: "Pull B", dayLabel: "Tomorrow", date: now, exerciseCount: 4, estimatedMinutes: 48
        )
        #expect(session.detailLine == "Tomorrow · 48 min")
    }

    @Test("a session survives a round trip through JSON, and an old payload without it still decodes")
    func codable() throws {
        let session = NextPlannedSession(
            routineName: "Push A", dayLabel: "Wed", date: now, exerciseCount: 5, estimatedMinutes: 52
        )
        let data = try JSONEncoder().encode(session)
        #expect(try JSONDecoder().decode(NextPlannedSession.self, from: data) == session)

        struct Payload: Codable, Equatable {
            var streakWeeks: Int
            var nextSession: NextPlannedSession?
        }
        let old = Data(#"{"streakWeeks":3}"#.utf8)
        let decoded = try JSONDecoder().decode(Payload.self, from: old)
        #expect(decoded == Payload(streakWeeks: 3, nextSession: nil))
    }

    @Test("the line is the top card's title, and nil without cards")
    func lineFromCards() {
        #expect(CoachGlance.line(from: []) == nil)
        let cards = [
            card("Bench Press has stalled", severity: .warning),
            card("New PR: Squat", severity: .info)
        ]
        #expect(CoachGlance.line(from: cards) == "Bench Press has stalled")
    }

    @Test("a long title is cut to the limit on a word boundary with an ellipsis")
    func trimming() {
        let long = "Bench Press's e1RM is trending down across the last four sessions you logged"
        let line = CoachGlance.trimmed(long, to: 60)
        #expect(line.count <= 60)
        #expect(line.hasSuffix("…"))
        #expect(!line.contains("  "))
        #expect(line == "Bench Press's e1RM is trending down across the last four…")

        // No usable space near the cut: hard cut instead of losing most of the line.
        let unbroken = String(repeating: "a", count: 80)
        #expect(CoachGlance.trimmed(unbroken, to: 10) == String(repeating: "a", count: 9) + "…")
        // Short lines and collapsed whitespace come back untouched otherwise.
        #expect(CoachGlance.trimmed("A deload\n looks due", to: 60) == "A deload looks due")
    }

    private func card(_ title: String, severity: CoachSeverity) -> CoachCard {
        CoachCard(
            rule: .stalledLift, severity: severity, title: title, body: "", evidence: [],
            distinguishingKey: title, firedDate: now
        )
    }
}
