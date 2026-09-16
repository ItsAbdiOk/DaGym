import Foundation
import Testing

@testable import GymCore

@Suite("CoachWeekReview: the week under review, when a check-in is due, and the canned turn")
struct CoachWeekReviewTests {
    private let calendar = CoachTestSupport.calendar
    /// Sunday.
    private let sunday = CoachTestSupport.date("2026-09-13T15:00:00Z")
    /// The Tuesday after.
    private let tuesday = CoachTestSupport.date("2026-09-15T08:00:00Z")

    @Test("the week ends on today when it is Sunday, else on the Sunday just gone")
    func weekEnding() {
        let onSunday = CoachWeekReview.weekEnding(now: sunday, calendar: calendar)
        #expect(DateKey.string(for: onSunday, calendar: calendar) == "2026-09-13")
        #expect(CoachWeekReview.weekKey(now: tuesday, calendar: calendar) == "2026-09-13")
        let saturday = CoachTestSupport.date("2026-09-19T23:00:00Z")
        #expect(CoachWeekReview.weekKey(now: saturday, calendar: calendar) == "2026-09-13")
        let start = CoachWeekReview.weekStart(weekEnding: onSunday, calendar: calendar)
        #expect(DateKey.string(for: start, calendar: calendar) == "2026-09-07")
    }

    @Test("workouts are counted over the Monday-to-Sunday window only")
    func workoutCount() {
        let weekEnding = CoachWeekReview.weekEnding(now: tuesday, calendar: calendar)
        let dates = [
            CoachTestSupport.date("2026-09-06T18:00:00Z"), // the Sunday before: out
            CoachTestSupport.date("2026-09-07T07:00:00Z"), // Monday: in
            CoachTestSupport.date("2026-09-10T18:00:00Z"),
            CoachTestSupport.date("2026-09-13T21:00:00Z"), // Sunday evening: in
            CoachTestSupport.date("2026-09-14T06:00:00Z") // Monday after: out
        ]
        #expect(CoachWeekReview.workoutCount(dates: dates, weekEnding: weekEnding, calendar: calendar) == 3)
    }

    @Test("due needs the chat configured, two workouts, and nothing started, done or dismissed")
    func due() {
        var status = CoachWeekReview.Status(
            weekKey: "2026-09-13", workoutCount: 2, isConfigured: true, hasThread: false
        )
        #expect(status.isDue)
        #expect(status.isVisible)
        status.workoutCount = 1
        #expect(!status.isDue)
        #expect(!status.isVisible)
        status.workoutCount = 3
        status.isConfigured = false
        #expect(!status.isDue)
        status.isConfigured = true
        status.dismissedWeekKey = "2026-09-13"
        #expect(!status.isDue)
        #expect(!status.isVisible)
        status.dismissedWeekKey = "2026-09-06"
        #expect(status.isDue)
        status.lastReviewedWeekKey = "2026-09-13"
        #expect(!status.isDue)
        status.lastReviewedWeekKey = nil
        status.hasThread = true
        #expect(!status.isDue)
        #expect(status.isVisible)
    }

    @Test("the canned turn names the window, the reads and asks for exactly one proposal")
    func userTurn() {
        let weekEnding = CoachWeekReview.weekEnding(now: tuesday, calendar: calendar)
        let turn = CoachWeekReviewPrompt.userTurn(weekEnding: weekEnding, calendar: calendar)
        #expect(turn.hasPrefix("Weekly check-in for 2026-09-07 to 2026-09-13."))
        for tool in ["get_recent_workouts", "get_exercise_history", "get_muscle_volume", "propose_*"] {
            #expect(turn.contains(tool))
        }
        #expect(turn.contains("one proposal, not several"))
        #expect(turn.contains("under 200 words"))
    }

    @Test("the headline is the first non-empty line, trimmed to the cap")
    func headline() {
        #expect(CoachWeekReviewPrompt.headline(from: "\n  \nBench moved up.\nMore.") == "Bench moved up.")
        #expect(CoachWeekReviewPrompt.headline(from: "   ") == nil)
        let long = String(repeating: "x", count: 200)
        #expect(CoachWeekReviewPrompt.headline(from: long)?.count == 120)
        #expect(CoachWeekReviewPrompt.headline(from: long)?.hasSuffix("…") == true)
    }
}
