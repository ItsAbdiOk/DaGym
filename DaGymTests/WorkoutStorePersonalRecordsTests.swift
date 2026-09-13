import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore.personalRecords")
struct WorkoutStorePersonalRecordsTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(store: WorkoutStore, exerciseIDs: [UUID]) -> UUID {
        let drafts = exerciseIDs.map {
            RoutineExerciseDraft(
                exerciseID: $0,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 20),
                    PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
                ]
            )
        }
        return store.saveRoutine(id: nil, name: "Push A", exercises: drafts).id
    }

    @Test("groups cached records by exercise, newest first, with a formatted line")
    func groupsByExercise() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let squat = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [bench.id, squat.id])

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 80
        session.exercises[0].sets[1].reps = 5
        session.exercises[0].sets[1].isDone = true
        session.exercises[1].sets[1].weightKg = 120
        session.exercises[1].sets[1].reps = 5
        session.exercises[1].sets[1].isDone = true
        _ = store.finish(session: session)

        let groups = store.personalRecords()

        #expect(groups.map(\.exerciseName) == ["Bench Press", "Squat"])
        let benchGroup = try #require(groups.first { $0.exerciseName == "Bench Press" })
        let record = try #require(benchGroup.records.first)
        #expect(record.kindLabel == "Estimated 1RM")
        #expect(!record.line.isEmpty)
    }

    @Test("an exercise with no cached record is not listed")
    func noRecordMeansNotListed() throws {
        let store = try makeStore()
        _ = store.createCustomExercise(
            name: "Plank", primary: [.abs], equipment: "Bodyweight", style: .bodyweightReps
        )

        let groups = store.personalRecords()
        #expect(!groups.contains { $0.exerciseName == "Plank" })
    }
}
