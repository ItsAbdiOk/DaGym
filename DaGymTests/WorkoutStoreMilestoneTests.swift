import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore milestones")
struct WorkoutStoreMilestoneTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    @Test("finishing 10 workouts earns the workout-count bronze milestone once")
    func workoutCountBronzeEarnedOnce() throws {
        let store = try makeStore()
        var lastSummary: WorkoutSummary?
        for _ in 0..<10 {
            let session = store.startFreestyle()
            lastSummary = store.finish(session: session)
        }
        let summary = try #require(lastSummary)
        #expect(summary.achievements.contains { $0.milestoneID == "workoutCount" && $0.tier == .bronze })

        let nextSession = store.startFreestyle()
        let nextSummary = store.finish(session: nextSession)
        #expect(!nextSummary.achievements.contains { $0.milestoneID == "workoutCount" })
    }

    @Test("milestoneProgress reports the fraction toward the next tier")
    func progressFractions() throws {
        let store = try makeStore()
        for _ in 0..<3 {
            let session = store.startFreestyle()
            _ = store.finish(session: session)
        }
        let progress = store.milestoneProgress(weeklyGoal: 4)
        let workoutCount = try #require(progress.first { $0.definition.id == "workoutCount" })
        #expect(workoutCount.currentTier == nil)
        #expect(workoutCount.nextThreshold == 10)
        #expect(abs(workoutCount.progress - 0.3) < 0.001)
    }

    @Test("a strength milestone earns once a lift and bodyweight are both on file")
    func strengthMilestoneEarned() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80)
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id, sets: [PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 60)]
        )
        let routine = store.saveRoutine(id: nil, name: "Push", exercises: [draft])
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].weightKg = 60
        session.exercises[0].sets[0].reps = 5
        session.exercises[0].sets[0].isDone = true

        let summary = store.finish(session: session)
        #expect(summary.achievements.contains { $0.milestoneID == "strength.bench" })
    }

    @Test("a strength milestone never earns without a logged bodyweight")
    func strengthMilestoneNeedsBodyweight() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id, sets: [PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 60)]
        )
        let routine = store.saveRoutine(id: nil, name: "Push", exercises: [draft])
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].weightKg = 60
        session.exercises[0].sets[0].reps = 5
        session.exercises[0].sets[0].isDone = true

        let summary = store.finish(session: session)
        #expect(!summary.achievements.contains { $0.milestoneID == "strength.bench" })
    }

    @Test("a backfilled workout still earns milestones but the summary doesn't celebrate them")
    func backfillEarnsWithoutCelebrating() throws {
        let store = try makeStore()
        for _ in 0..<9 {
            let session = store.startFreestyle()
            _ = store.finish(session: session)
        }
        let past = Date().addingTimeInterval(-86_400 * 10)
        let session = store.startBackfill(date: past, durationMinutes: 45, routineID: nil)

        let summary = store.finish(session: session)
        #expect(summary.achievements.isEmpty)
        #expect(store.achievements().contains { $0.milestoneID == "workoutCount" && $0.tier == .bronze })
    }

    // MARK: - F4: strength milestones match on identity, not a name substring

    /// Logs one heavy set of `exercise` and returns the resulting achievements.
    private func logHeavySet(
        store: WorkoutStore, exerciseID: UUID, weightKg: Double
    ) -> [AchievementInfo] {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: weightKg)]
        )
        let routine = store.saveRoutine(id: nil, name: "Session \(weightKg)", exercises: [draft])
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].weightKg = weightKg
        session.exercises[0].sets[0].reps = 5
        session.exercises[0].sets[0].isDone = true
        return store.finish(session: session).achievements
    }

    @Test("a hack squat is not the squat, however heavy it is")
    func hackSquatEarnsNoSquatMilestone() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let hackSquat = store.createCustomExercise(
            name: "Hack Squat", primary: [.quads], equipment: "machine", style: .weightReps
        )
        // 180 × 5 at 80 kg bodyweight used to be 2× bodyweight and earn Gold.
        let achievements = logHeavySet(store: store, exerciseID: hackSquat.id, weightKg: 180)
        #expect(!achievements.contains { $0.milestoneID == "strength.squat" })
        #expect(!store.achievements().contains { $0.milestoneID == "strength.squat" })
    }

    @Test("a Romanian deadlift is not the deadlift")
    func romanianDeadliftEarnsNoDeadliftMilestone() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let rdl = store.createCustomExercise(
            name: "Romanian Deadlift", primary: [.hams], equipment: "Barbell", style: .weightReps
        )
        let achievements = logHeavySet(store: store, exerciseID: rdl.id, weightKg: 150)
        #expect(!achievements.contains { $0.milestoneID == "strength.deadlift" })
    }

    @Test("a dumbbell shoulder press is not the barbell overhead press")
    func dumbbellShoulderPressEarnsNoOHPMilestone() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let press = store.createCustomExercise(
            name: "Dumbbell Shoulder Press", primary: [.delts], equipment: "dumbbell",
            style: .weightReps
        )
        // 40 kg *per bell* used to count as a 40 kg barbell press — half the real load.
        let achievements = logHeavySet(store: store, exerciseID: press.id, weightKg: 45)
        #expect(!achievements.contains { $0.milestoneID == "strength.ohp" })
    }

    @Test("the barbell squat itself still earns the squat milestone")
    func barbellSquatStillEarns() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let squat = store.createCustomExercise(
            name: "Back Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let achievements = logHeavySet(store: store, exerciseID: squat.id, weightKg: 100)
        #expect(achievements.contains { $0.milestoneID == "strength.squat" })
    }

    @Test("a bodyweight squat can never earn the squat milestone")
    func bodyweightSquatEarnsNoSquatMilestone() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let airSquat = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "bodyweight", style: .bodyweightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: airSquat.id, sets: [PlannedSetDraft(kind: .working, targetReps: 12)]
        )
        let routine = store.saveRoutine(id: nil, name: "Air", exercises: [draft])
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].weightKg = 0
        session.exercises[0].sets[0].reps = 12
        session.exercises[0].sets[0].isDone = true
        let summary = store.finish(session: session)
        #expect(!summary.achievements.contains { $0.milestoneID == "strength.squat" })
        #expect(!store.achievements().contains { $0.milestoneID == "strength.squat" })
    }

    // MARK: - F9: backfilled milestones are dated by the session that earned them

    @Test("a backfilled workout's milestone is stamped with the session's date, not today")
    func backfilledMilestoneIsDatedByTheSession() throws {
        let store = try makeStore()
        for _ in 0..<9 {
            _ = store.finish(session: store.startFreestyle())
        }
        let past = Date().addingTimeInterval(-86_400 * 30)
        _ = store.finish(
            session: store.startBackfill(date: past, durationMinutes: 45, routineID: nil)
        )
        let models = store.fetch(FetchDescriptor<AchievementModel>())
        let bronze = try #require(models.first { $0.milestoneID == "workoutCount" })
        #expect(abs(bronze.earnedAt.timeIntervalSince(past)) < 1)
    }

    @Test("bodyweightSeries and recentBodyMeasurements return logged readings, newest last/first")
    func bodyweightSeriesAndRecent() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80, date: Date().addingTimeInterval(-86_400 * 2), source: "manual")
        store.logBodyweight(kg: 79, date: Date(), source: "health")

        let series = store.bodyweightSeries()
        #expect(series.map(\.kg) == [80, 79])

        let recent = store.recentBodyMeasurements()
        #expect(recent.first?.kg == 79)
        #expect(recent.first?.source == "health")
    }
}
