import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Store parity: insights")
struct ParityStoreInsightsTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeExercise(
        _ store: WorkoutStore, name: String, primary: [Muscle] = [.chest]
    ) -> ExerciseInfo {
        store.createCustomExercise(name: name, primary: primary, equipment: "Barbell", style: .weightReps)
    }

    private func makeRoutine(
        _ store: WorkoutStore, name: String = "Push A", exerciseID: UUID, setCount: Int = 3
    ) -> UUID {
        let set = PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 80)
        let draft = RoutineExerciseDraft(exerciseID: exerciseID, sets: Array(repeating: set, count: setCount))
        return store.saveRoutine(id: nil, name: name, exercises: [draft]).id
    }

    private func logSession(
        _ store: WorkoutStore, routineID: UUID, weightKg: Double, reps: Int, backfilledAt: Date? = nil
    ) -> WorkoutSummary {
        let session = backfilledAt.map {
            store.startBackfill(date: $0, durationMinutes: 45, routineID: routineID)
        } ?? store.startWorkout(routineID: routineID)
        for index in session.exercises[0].sets.indices {
            session.exercises[0].sets[index].weightKg = weightKg
            session.exercises[0].sets[index].reps = reps
            session.exercises[0].sets[index].isDone = true
        }
        return store.finish(session: session)
    }

    // MARK: - Rec 5: "vs last time"

    @Test("the summary compares against the previous run of the same routine")
    func summaryCarriesPrevious() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let routineID = makeRoutine(store, exerciseID: bench.id)
        let first = logSession(store, routineID: routineID, weightKg: 80, reps: 5)
        #expect(first.previous == nil)

        let second = logSession(store, routineID: routineID, weightKg: 100, reps: 5)
        let previous = try #require(second.previous)
        #expect(previous.volumeKg == 1200)
        #expect(second.volumeKg - previous.volumeKg == 300)
        #expect(previous.setsDone == 3)
        let change = try #require(second.e1rmChanges.first { $0.exerciseID == bench.id })
        let current = try #require(change.current)
        let before = try #require(change.previous)
        #expect(current > before)
    }

    @Test("a different routine's first run has no previous")
    func firstRunOfRoutineHasNoPrevious() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let push = makeRoutine(store, name: "Push A", exerciseID: bench.id)
        let legs = makeRoutine(store, name: "Legs", exerciseID: bench.id)
        _ = logSession(store, routineID: push, weightKg: 80, reps: 5)
        #expect(logSession(store, routineID: legs, weightKg: 80, reps: 5).previous == nil)
    }

    @Test("a backfill dated before the last run compares against the latest one before its own date")
    func backfillComparesAgainstEarlierRun() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let routineID = makeRoutine(store, exerciseID: bench.id)
        let day: TimeInterval = 86_400
        let oldest = logSession(
            store, routineID: routineID, weightKg: 60, reps: 5,
            backfilledAt: Date(timeIntervalSinceNow: -10 * day)
        )
        _ = logSession(store, routineID: routineID, weightKg: 100, reps: 5)
        let between = logSession(
            store, routineID: routineID, weightKg: 80, reps: 5,
            backfilledAt: Date(timeIntervalSinceNow: -5 * day)
        )

        #expect(oldest.previous == nil)
        #expect(between.previous?.volumeKg == 900)
    }

    // MARK: - Rec 6: duplicate routine

    @Test("duplicating names the copy (Copy), then (Copy 2), and never nests")
    func duplicateRoutineNaming() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let routineID = makeRoutine(store, exerciseID: bench.id)

        let copy = try #require(store.duplicateRoutine(id: routineID))
        #expect(copy.name == "Push A (Copy)")
        #expect(copy.id != routineID)
        let second = try #require(store.duplicateRoutine(id: copy.id))
        #expect(second.name == "Push A (Copy 2)")
        let third = try #require(store.duplicateRoutine(id: routineID))
        #expect(third.name == "Push A (Copy 3)")
        #expect(store.duplicateRoutine(id: UUID()) == nil)
        #expect(store.fetchRoutineModel(id: copy.id)?.importedFromID == nil)
    }

    @Test("mutating the copy's sets leaves the original untouched")
    func duplicateRoutineIsDeep() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let routineID = makeRoutine(store, exerciseID: bench.id)
        let copy = try #require(store.duplicateRoutine(id: routineID))

        var drafts = try #require(store.routineDrafts(id: copy.id)).drafts
        #expect(drafts.first?.sets.count == 3)
        drafts[0].sets.append(PlannedSetDraft(targetReps: 10, targetWeightKg: 60))
        store.saveRoutine(id: copy.id, name: copy.name, exercises: drafts)

        #expect(store.routineDrafts(id: copy.id)?.drafts.first?.sets.count == 4)
        #expect(store.routineDrafts(id: routineID)?.drafts.first?.sets.count == 3)
        #expect(store.routineDrafts(id: routineID)?.info.name == "Push A")
    }

    // MARK: - Rec 8: untrained muscles in body order

    @Test("untrained muscles list in body order, not alphabetically")
    func untrainedMusclesInBodyOrder() throws {
        let store = try makeStore()
        let trained = Muscle.allCases.filter { $0 != .hams && $0 != .chest }
        let everything = makeExercise(store, name: "Everything", primary: trained)
        let routineID = makeRoutine(store, exerciseID: everything.id, setCount: 1)
        _ = logSession(store, routineID: routineID, weightKg: 50, reps: 5)

        #expect(store.recoverySnapshot().untrainedMuscles == [.chest, .hams])
    }
}
