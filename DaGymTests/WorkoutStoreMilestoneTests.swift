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
