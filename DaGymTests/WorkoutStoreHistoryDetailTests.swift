import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore history detail")
struct WorkoutStoreHistoryDetailTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    @Test("lifetimeStats sums only finished workouts, excluding warm-up volume")
    func lifetimeStatsSumsFinishedWorkouts() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let first = store.startWorkout(routineID: routineID)
        first.exercises[0].sets[0].isDone = true
        first.exercises[0].sets[1].weightKg = 60
        first.exercises[0].sets[1].reps = 8
        first.exercises[0].sets[1].isDone = true
        _ = store.finish(session: first)

        let second = store.startWorkout(routineID: routineID)
        second.exercises[0].sets[1].weightKg = 70
        second.exercises[0].sets[1].reps = 5
        second.exercises[0].sets[1].isDone = true
        _ = store.finish(session: second)

        _ = store.startWorkout(routineID: routineID)

        let stats = store.lifetimeStats()
        #expect(stats.workouts == 2)
        #expect(stats.volumeKg == 60 * 8 + 70 * 5)
    }

    @Test("workoutDetail returns exercises, sets and PR count for a finished workout")
    func workoutDetailReturnsFullBreakdown() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Deadlift", primary: [.hams], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        session.exercises[0].sets[1].weightKg = 120
        session.exercises[0].sets[1].reps = 5
        session.exercises[0].sets[1].isDone = true
        let summary = store.finish(session: session)

        guard let workoutID = session.workoutID else {
            Issue.record("session missing workoutID")
            return
        }
        let detail = store.workoutDetail(id: workoutID)

        #expect(detail.exercises.map(\.exercise.name) == ["Deadlift"])
        #expect(detail.exercises.first?.sets.count == 2)
        #expect(detail.setsDone == 1) // the warm-up doesn't count, matching the recap and Health
        #expect(detail.volumeKg == 120 * 5)
        #expect(detail.prCount == summary.prs.count)
        #expect(detail.isBackfilled == false)
    }

    @Test("a single-routine workout collapses to one ungrouped run with no header")
    func singleRoutineWorkoutHasNoGroupHeader() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Deadlift", primary: [.hams], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let detail = store.workoutDetail(id: try #require(session.workoutID))
        #expect(detail.exerciseGroups.count == 1)
        #expect(detail.exerciseGroups[0].glyph == nil)
        #expect(detail.exerciseGroups[0].exercises.count == 1)
    }

    @Test("a freestyle workout collapses to one ungrouped run with no header")
    func freestyleWorkoutHasNoGroupHeader() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Push-up", primary: [.chest], equipment: "Bodyweight", style: .bodyweightReps
        )
        let session = store.startFreestyle()
        let entry = store.autoFilledEntry(for: exercise)
        session.exercises = [entry]
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        let detail = store.workoutDetail(id: try #require(session.workoutID))
        #expect(detail.exerciseGroups.count == 1)
        #expect(detail.exerciseGroups[0].glyph == nil)
    }

    @Test("a workout built from two routines groups its exercises one group per routine, glyph included")
    func multiRoutineWorkoutGroupsByRoutine() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let curl = store.createCustomExercise(
            name: "Curl", primary: [.biceps], equipment: "Dumbbell", style: .weightReps
        )
        let pushID = makeRoutine(store: store, exerciseID: bench.id)
        let armsDraft = RoutineExerciseDraft(
            exerciseID: curl.id, sets: [PlannedSetDraft(kind: .working, targetReps: 10, targetWeightKg: 15)]
        )
        let armsID = store.saveRoutine(id: nil, name: "Arms", exercises: [armsDraft]).id

        let session = store.startWorkout(routineID: pushID)
        store.appendRoutine(id: armsID, to: session)
        #expect(session.routineGlyphs[pushID]?.name == "Push A")
        #expect(session.routineGlyphs[armsID]?.name == "Arms")
        #expect(session.exercises.map(\.routineID) == [pushID, armsID])
        for index in session.exercises.indices {
            session.exercises[index].sets[session.exercises[index].sets.count - 1].isDone = true
        }
        _ = store.finish(session: session)

        let detail = store.workoutDetail(id: try #require(session.workoutID))
        #expect(detail.exerciseGroups.count == 2)
        #expect(detail.exerciseGroups.map(\.routineID) == [pushID, armsID])
        #expect(detail.exerciseGroups[0].glyph?.name == "Push A")
        #expect(detail.exerciseGroups[1].glyph?.name == "Arms")
        #expect(detail.exerciseGroups[0].exercises.map(\.exercise.name) == ["Bench Press"])
        #expect(detail.exerciseGroups[1].exercises.map(\.exercise.name) == ["Curl"])
    }
}

/// Assisted machines log the *assistance* as the row's weight, so every "weight × reps" total
/// has to read the lifted load instead — see `ExerciseInfo.LoggingStyle.loadedWeightKg(logged:)`.
/// The convention is that an assisted set's volume is zero; these pin it down at each of the
/// four totals a user can see, and pin the live number to the History one.
@MainActor
@Suite("Volume and tonnage — assisted lifts")
struct WorkoutStoreAssistedVolumeTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    /// One working set per exercise, so `sets[0]` is the set to log.
    private func makeRoutine(store: WorkoutStore, exerciseIDs: [UUID]) -> UUID {
        let drafts = exerciseIDs.map {
            RoutineExerciseDraft(
                exerciseID: $0, sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
            )
        }
        return store.saveRoutine(id: nil, name: "Pull A", exercises: drafts).id
    }

    private func assisted(_ store: WorkoutStore) -> ExerciseInfo {
        store.createCustomExercise(
            name: "Assisted Pull-Up", primary: [.lats], equipment: "machine", style: .assisted
        )
    }

    private func log(_ session: WorkoutSession, _ index: Int, weight: Double, reps: Int) {
        session.exercises[index].sets[0].weightKg = weight
        session.exercises[index].sets[0].reps = reps
        session.exercises[index].sets[0].isDone = true
    }

    @Test("30 kg of assistance × 8 adds nothing to the session, the workout or lifetime tonnage")
    func assistedSetsAddNoVolume() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80)
        let routineID = makeRoutine(store: store, exerciseIDs: [assisted(store).id])

        let session = store.startWorkout(routineID: routineID)
        log(session, 0, weight: 30, reps: 8)
        // The live header: 30 kg of help is not 240 kg lifted.
        #expect(session.volumeKg == 0)

        let summary = store.finish(session: session)
        #expect(summary.volumeKg == 0)

        let record = try #require(store.history().first)
        #expect(record.volumeKg == 0)
        #expect(record.sets == 1)
        #expect(store.lifetimeStats().volumeKg == 0)
        let detail = store.workoutDetail(id: try #require(session.workoutID))
        #expect(detail.volumeKg == 0)
    }

    @Test("a mixed workout counts the barbell work and only the barbell work")
    func mixedWorkoutCountsOnlyLoadedExercises() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80)
        let row = store.createCustomExercise(
            name: "Barbell Row", primary: [.lats], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [row.id, assisted(store).id])

        let session = store.startWorkout(routineID: routineID)
        log(session, 0, weight: 60, reps: 10)
        log(session, 1, weight: 30, reps: 8)
        #expect(session.volumeKg == 600)

        _ = store.finish(session: session)
        #expect(store.lifetimeStats().volumeKg == 600)
        #expect(try #require(store.history().first).volumeKg == 600)
    }

    @Test("the live session's volume and History's volume are the same number")
    func liveVolumeMatchesHistory() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80)
        let row = store.createCustomExercise(
            name: "Barbell Row", primary: [.lats], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [row.id, assisted(store).id])

        let session = store.startWorkout(routineID: routineID)
        log(session, 0, weight: 72.5, reps: 9)
        log(session, 1, weight: 25, reps: 12)
        let live = session.volumeKg

        let summary = store.finish(session: session)
        let record = try #require(store.history().first)
        let detail = store.workoutDetail(id: try #require(session.workoutID))
        #expect(live == summary.volumeKg)
        #expect(live == record.volumeKg)
        #expect(live == detail.volumeKg)
        #expect(live == store.lifetimeStats().volumeKg)
    }

    @Test("assistance can't unlock the Lifetime Tonnage milestone, load can")
    func tonnageMilestoneIgnoresAssistance() throws {
        func bronzeEarned(style: ExerciseInfo.LoggingStyle) throws -> Bool {
            let store = try makeStore()
            store.logBodyweight(kg: 80)
            let exercise = store.createCustomExercise(
                name: "Machine", primary: [.lats], equipment: "machine", style: style
            )
            let routineID = makeRoutine(store: store, exerciseIDs: [exercise.id])
            let session = store.startWorkout(routineID: routineID)
            // 100 kg × 1 000 reps = the 100 000 kg bronze threshold exactly.
            log(session, 0, weight: 100, reps: 1_000)
            let summary = store.finish(session: session)
            let expected: Double = style == .assisted ? 0 : 100_000
            #expect(store.milestoneState(weeklyGoal: 4).lifetimeTonnageKg == expected)
            return summary.achievements.contains { $0.milestoneID == "lifetimeTonnage" }
        }
        #expect(try bronzeEarned(style: .weightReps))
        #expect(try !bronzeEarned(style: .assisted))
    }
}
