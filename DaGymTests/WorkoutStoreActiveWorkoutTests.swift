import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore active-workout mutations")
struct WorkoutStoreActiveWorkoutTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    @Test("discard deletes the backing workout")
    func discardDeletesWorkout() throws {
        let store = try makeStore()
        let session = store.startFreestyle()
        let workoutID = try #require(session.workoutID)
        #expect(store.workout(id: workoutID) != nil)

        store.discard(session: session)

        #expect(store.workout(id: workoutID) == nil)
        #expect(store.history().isEmpty)
    }

    @Test("autoFilledEntry gives three working sets, filled from the previous session")
    func autoFilledEntryFillsFromPrevious() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Lat Pulldown", primary: [.lats], equipment: "Cable", style: .weightReps
        )

        let first = store.startFreestyle()
        let firstEntry = store.autoFilledEntry(for: exercise)
        #expect(firstEntry.sets.count == 3)
        #expect(firstEntry.sets.allSatisfy { $0.kind == .working })

        first.exercises.append(firstEntry)
        first.exercises[0].sets[1].weightKg = 55
        first.exercises[0].sets[1].reps = 10
        first.exercises[0].sets[1].isDone = true
        _ = store.finish(session: first)

        let second = store.startFreestyle()
        let secondEntry = store.autoFilledEntry(for: exercise)
        #expect(secondEntry.sets[1].weightKg == 55)
        #expect(secondEntry.sets[1].reps == 10)
        #expect(secondEntry.sets[1].previous == "55 × 10")
        store.discard(session: second)
    }
}
