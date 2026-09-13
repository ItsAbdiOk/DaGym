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

    @Test("an assisted pull-up session earns an e1RM PR and a least-assistance PR")
    func assistedPullUpEarnsE1rmAndLeastAssistancePRs() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80)
        let pullUp = store.createCustomExercise(
            name: "Assisted Pull-Up", primary: [.lats], equipment: "machine", style: .assisted
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [pullUp.id])

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 0
        session.exercises[0].sets[1].reps = 6
        session.exercises[0].sets[1].assistanceKg = 20
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let group = try #require(store.personalRecords().first { $0.exerciseName == "Assisted Pull-Up" })
        #expect(group.records.contains { $0.kindLabel == "Estimated 1RM" })
        #expect(group.records.contains { $0.kindLabel == "Least assistance" })
    }

    @Test("a weighted pull-up's e1RM reflects bodyweight + added load, not the added load alone")
    func weightedPullUpE1rmIncludesBodyweight() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80)
        let pullUp = store.createCustomExercise(
            name: "Weighted Pull-Up", primary: [.lats], equipment: "other", style: .weightedBodyweight
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [pullUp.id])

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 20
        session.exercises[0].sets[1].reps = 5
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let group = try #require(store.personalRecords().first { $0.exerciseName == "Weighted Pull-Up" })
        let record = try #require(group.records.first { $0.kindLabel == "Estimated 1RM" })
        // "e1RM 23" would mean the added-weight-only bug; the real e1RM off bodyweight (80) + 20
        // at 5 reps is well above bodyweight.
        #expect(record.line.contains("e1RM 23") == false)
    }
}
