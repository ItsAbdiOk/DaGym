import Foundation
import Testing
@testable import GymCore

@Suite("Coach engine")
struct CoachEngineTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    @Test("empty history produces no cards and doesn't crash")
    func emptyHistoryProducesNoCards() {
        let cards = CoachEngine.cards(for: CoachInput(), now: now, calendar: calendar)
        #expect(cards.isEmpty)
    }

    @Test("a brand-new lifter with three workouts isn't buried in cards")
    func newLifterIsNotBuried() {
        let dates = (0..<3).map { CoachTestSupport.daysAgo($0 * 2, from: now) }
        let input = CoachInput(
            workoutDates: dates,
            recentSessions: dates.map {
                CoachSessionSummary(
                    date: $0, plannedSetCount: 12, completedSetCount: 12, durationSeconds: 2400
                )
            },
            lifts: [
                CoachLiftSnapshot(name: "Squat", stallState: StallState(), e1rmTrend: [80, 82, 85])
            ]
        )
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.count <= 2)
    }

    /// Deliberately over-provisions evidence for every rule so more than
    /// `TrainingConstants.coachMaxCards` would otherwise fire, and checks the cap actually engages.
    @Test("output is capped even when many rules fire at once")
    func outputIsCapped() {
        let liftA = CoachLiftSnapshot(
            name: "Bench Press", stallState: StallState(consecutiveMisses: 3, lastWeightKg: 60),
            e1rmTrend: [100, 100, 95, 90], lastWorkingWeightKg: 60, lastWorkingSetCount: 4
        )
        let liftB = CoachLiftSnapshot(
            name: "Squat", stallState: StallState(consecutiveMisses: 4, lastWeightKg: 100),
            e1rmTrend: [], lastWorkingWeightKg: 100, lastWorkingSetCount: 4
        )
        let strugglingCandidate = SubstitutionCandidate(
            id: UUID(), name: "Overhead Press", primary: [.delts], equipment: "barbell", mechanic: "compound"
        )
        let substitute = SubstitutionCandidate(
            id: UUID(), name: "Dumbbell Shoulder Press", primary: [.delts], equipment: "dumbbell",
            mechanic: "compound"
        )
        let strugglingLift = CoachLiftSnapshot(
            name: "Overhead Press", stallState: StallState(), e1rmTrend: [],
            consecutiveFailedSessions: 3, substitutionCandidate: strugglingCandidate
        )

        // Adherence needs its own shape: the two weeks right before `now`'s own week barely
        // touched, and the two weeks before that fully attended as the baseline — otherwise the
        // rule sees a zero baseline and stays quiet instead of showing a real drop.
        let fullWeekOffsets = [0, 1, 2, 3] // Mon-Thu
        let sparseWeekOffsets = [0] // Mon only
        let priorWeek1 = CoachTestSupport.date("2023-12-11T00:00:00Z")
        let priorWeek2 = CoachTestSupport.date("2023-12-18T00:00:00Z")
        let recentWeek1 = CoachTestSupport.date("2023-12-25T00:00:00Z")
        let recentWeek2 = CoachTestSupport.date("2024-01-01T00:00:00Z")
        let adherenceDates = [priorWeek1, priorWeek2].flatMap { monday in
            fullWeekOffsets.compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        } + [recentWeek1, recentWeek2].flatMap { monday in
            sparseWeekOffsets.compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        }

        let input = CoachInput(
            schedule: WeeklySchedule(dayRoutines: [
                .monday: [UUID()], .tuesday: [UUID()], .wednesday: [UUID()], .thursday: [UUID()]
            ]),
            workoutDates: adherenceDates,
            recentSessions: (1...12).map { index in
                CoachSessionSummary(
                    date: CoachTestSupport.daysAgo(13 - index, from: now), plannedSetCount: 10,
                    completedSetCount: index <= 8 ? 10 : 4, durationSeconds: index <= 8 ? 3600 : 1200
                )
            },
            muscleSetsInWindow: [.chest: 10, .hams: 1],
            trackedMuscles: [.chest, .hams],
            lifts: [liftA, liftB, strugglingLift],
            hardWeeksInARow: 0,
            substitutionLibrary: [strugglingCandidate, substitute],
            availableEquipment: ["dumbbell"],
            recoveryMap: [.chest: 0.9, .quads: 0.85],
            recentPRs: [CoachPersonalRecordHighlight(
                exerciseName: "Deadlift",
                record: PersonalRecord(
                    kind: .e1rm, value: 180, weightKg: 150, reps: 3,
                    date: CoachTestSupport.daysAgo(1, from: now)
                )
            )],
            lastWorkoutDate: CoachTestSupport.daysAgo(60, from: now)
        )

        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(cards.count == TrainingConstants.coachMaxCards)
    }

    @Test("determinism: the same input, now and calendar always produce identical output")
    func isDeterministic() {
        let input = CoachInput(
            muscleSetsInWindow: [.chest: 10, .hams: 1], trackedMuscles: [.chest, .hams],
            lifts: [CoachLiftSnapshot(
                name: "Bench Press", stallState: StallState(consecutiveMisses: 3, lastWeightKg: 60),
                e1rmTrend: [], lastWorkingWeightKg: 60, lastWorkingSetCount: 4
            )],
            recoveryMap: [.chest: 0.9, .quads: 0.85]
        )
        let first = CoachEngine.cards(for: input, now: now, calendar: calendar)
        let second = CoachEngine.cards(for: input, now: now, calendar: calendar)
        #expect(first == second)
    }
}
