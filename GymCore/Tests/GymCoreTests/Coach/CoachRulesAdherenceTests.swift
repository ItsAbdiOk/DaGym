import Foundation
import Testing
@testable import GymCore

@Suite("Coach: adherence drop")
struct CoachRulesAdherenceTests {
    private let now = CoachTestSupport.date("2024-01-01T00:00:00Z") // Monday, in-progress week
    private let calendar = CoachTestSupport.calendar
    private let routineID = UUID()

    /// Monday–Thursday planned every week (4 planned days), so completion rates land on a clean
    /// 0/0.25/0.5/0.75/1 grid.
    private var schedule: WeeklySchedule {
        WeeklySchedule(dayRoutines: [
            .monday: [routineID], .tuesday: [routineID], .wednesday: [routineID], .thursday: [routineID]
        ])
    }

    private func week(mondayISO: String, attendedOffsets: [Int]) -> [Date] {
        let monday = CoachTestSupport.date(mondayISO)
        return attendedOffsets.compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// The two most recent complete weeks (before `now`'s own week) attend `recentOffsets` of the
    /// four planned days; the two weeks before that attend every planned day.
    private func workoutDates(recentOffsets: [Int]) -> [Date] {
        week(mondayISO: "2023-12-25T00:00:00Z", attendedOffsets: recentOffsets)
            + week(mondayISO: "2023-12-18T00:00:00Z", attendedOffsets: recentOffsets)
            + week(mondayISO: "2023-12-11T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
            + week(mondayISO: "2023-12-04T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
    }

    private func input(recentOffsets: [Int], interactions: [CoachInteraction] = []) -> CoachInput {
        CoachInput(
            schedule: schedule, workoutDates: workoutDates(recentOffsets: recentOffsets),
            interactions: interactions
        )
    }

    @Test("recent completion dropping to 1/4 vs a full prior baseline fires")
    func fires() {
        let cards = CoachEngine.cards(for: input(recentOffsets: [0]), now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .adherenceDrop })
    }

    @Test("a 3/4 recent rate (25% drop) stays under the 34% threshold and doesn't fire")
    func nearMissDoesNotFire() {
        let cards = CoachEngine.cards(for: input(recentOffsets: [0, 1, 2]), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .adherenceDrop })
    }

    @Test("a full recent rate matching the baseline doesn't fire")
    func noDropDoesNotFire() {
        let cards = CoachEngine.cards(for: input(recentOffsets: [0, 1, 2, 3]), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .adherenceDrop })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let mostRecentWeekStart = CoachTestSupport.date("2023-12-25T00:00:00Z")
        let fingerprint = CoachCard.makeFingerprint(
            rule: .adherenceDrop, key: DateKey.string(for: mostRecentWeekStart, calendar: calendar)
        )
        let interaction = CoachInteraction(
            rule: .adherenceDrop, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let cards = CoachEngine.cards(
            for: input(recentOffsets: [0], interactions: [interaction]), now: now, calendar: calendar
        )
        #expect(!cards.contains { $0.rule == .adherenceDrop })
    }
}
