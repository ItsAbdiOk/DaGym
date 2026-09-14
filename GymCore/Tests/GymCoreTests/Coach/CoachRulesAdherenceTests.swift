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

    // MARK: - What "completed" means

    /// The rule used to compare "days planned" with "days trained *anywhere* in the week", so
    /// training on three days that aren't in the plan scored as full adherence while every
    /// planned session was missed. Only planned days that were actually kept count now.
    @Test("training three unplanned days doesn't count as keeping the plan")
    func unplannedDaysDoNotCount() {
        // Recent two weeks: Friday/Saturday/Sunday only (offsets 4, 5, 6) — none of the four
        // planned Mon–Thu days. Prior two weeks: all four planned days.
        let dates = week(mondayISO: "2023-12-25T00:00:00Z", attendedOffsets: [4, 5, 6])
            + week(mondayISO: "2023-12-18T00:00:00Z", attendedOffsets: [4, 5, 6])
            + week(mondayISO: "2023-12-11T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
            + week(mondayISO: "2023-12-04T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
        let cards = CoachEngine.cards(
            for: CoachInput(schedule: schedule, workoutDates: dates), now: now, calendar: calendar
        )
        #expect(cards.contains { $0.rule == .adherenceDrop }, "0/4 against a 4/4 baseline is a drop")
    }

    /// Five trained days against four planned used to produce a completion "rate" of 1.25,
    /// which then dragged the recent-vs-prior comparison around. Every rate is now inside 0…1.
    @Test("extra sessions can't push a week's completion rate above 1")
    func rateNeverExceedsOne() {
        // Recent weeks: every planned day plus three extra ones. Prior weeks: every planned day.
        let dates = week(mondayISO: "2023-12-25T00:00:00Z", attendedOffsets: [0, 1, 2, 3, 4, 5, 6])
            + week(mondayISO: "2023-12-18T00:00:00Z", attendedOffsets: [0, 1, 2, 3, 4, 5, 6])
            + week(mondayISO: "2023-12-11T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
            + week(mondayISO: "2023-12-04T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
        let cards = CoachEngine.cards(
            for: CoachInput(schedule: schedule, workoutDates: dates), now: now, calendar: calendar
        )
        let card = cards.first { $0.rule == .adherenceDrop }
        #expect(card == nil, "training more than planned is not an adherence drop")
    }

    /// Apple Health imports belong in `workoutDates` (they broke the rest day, so `Streaks`
    /// counts them) but not in the adherence score: a week of running is not a week of keeping
    /// a lifting plan.
    @Test("health-imported sessions don't paper over missed planned days")
    func healthImportsDoNotCountAsAdherence() {
        let lifted = week(mondayISO: "2023-12-11T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
            + week(mondayISO: "2023-12-04T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
        let ranInstead = week(mondayISO: "2023-12-25T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
            + week(mondayISO: "2023-12-18T00:00:00Z", attendedOffsets: [0, 1, 2, 3])
        let input = CoachInput(
            schedule: schedule, workoutDates: lifted + ranInstead, loggedWorkoutDates: lifted
        )
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .adherenceDrop })
    }

    // MARK: - Scoring the past against the present plan

    /// The schedule holds only the *current* plan. Grading weeks that were lived under a
    /// different one rewrote the lifter's own adherence history the moment they moved a
    /// training day, so those weeks are no longer scored at all.
    @Test("a schedule changed mid-lookback suppresses the card instead of rewriting history")
    func scheduleChangedMidLookbackSuppresses() {
        let changedAt = CoachTestSupport.date("2023-12-20T00:00:00Z")
        let input = CoachInput(
            schedule: schedule, workoutDates: workoutDates(recentOffsets: [0]),
            scheduleUpdatedAt: changedAt
        )
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .adherenceDrop })
    }

    @Test("a schedule that predates the whole lookback still scores normally")
    func oldScheduleStillScores() {
        let input = CoachInput(
            schedule: schedule, workoutDates: workoutDates(recentOffsets: [0]),
            scheduleUpdatedAt: CoachTestSupport.date("2023-01-01T00:00:00Z")
        )
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .adherenceDrop })
    }
}
