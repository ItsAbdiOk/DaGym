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

    @Test("autoFilledEntry gives three working sets, filled by position from last session's completed sets")
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
        // Only completed sets count as a previous (A6), and position is counted among those —
        // so every set is completed here, with a distinct middle set to prove the matching.
        for index in 0..<3 {
            first.exercises[0].sets[index].weightKg = index == 1 ? 55 : 50
            first.exercises[0].sets[index].reps = index == 1 ? 10 : 12
            first.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: first)

        let second = store.startFreestyle()
        let secondEntry = store.autoFilledEntry(for: exercise)
        #expect(secondEntry.sets[1].weightKg == 55)
        #expect(secondEntry.sets[1].reps == 10)
        #expect(secondEntry.sets[1].previousWeightKg == 55)
        #expect(secondEntry.sets[1].previousReps == 10)
        #expect(secondEntry.sets[2].previousWeightKg == 50)
        store.discard(session: second)
    }

    @Test("autoFilledEntry skips uncompleted sets: completed ones fill by their own position, no ghost after")
    func autoFilledEntryIgnoresUncompletedSets() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Lat Pulldown", primary: [.lats], equipment: "Cable", style: .weightReps
        )

        let first = store.startFreestyle()
        first.exercises.append(store.autoFilledEntry(for: exercise))
        first.exercises[0].sets[1].weightKg = 55
        first.exercises[0].sets[1].reps = 10
        first.exercises[0].sets[1].isDone = true
        _ = store.finish(session: first)

        let second = store.startFreestyle()
        let secondEntry = store.autoFilledEntry(for: exercise)
        // The one completed set is previous #1, so it lands on (and ghosts) the first slot.
        #expect(secondEntry.sets[0].weightKg == 55)
        #expect(secondEntry.sets[0].previousWeightKg == 55)
        #expect(secondEntry.sets[0].previousReps == 10)
        // Later slots repeat it ("Like your last set") without claiming to be what was done there.
        #expect(secondEntry.sets[1].weightKg == 55)
        #expect(secondEntry.sets[1].previousWeightKg == nil)
        store.discard(session: second)
    }
}
