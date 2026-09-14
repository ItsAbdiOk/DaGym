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
        // Only one working set was completed last time, so that's the set count offered now,
        // and it lands on (and ghosts) the first slot.
        #expect(secondEntry.sets.count == 1)
        #expect(secondEntry.sets[0].weightKg == 55)
        #expect(secondEntry.sets[0].previousWeightKg == 55)
        #expect(secondEntry.sets[0].previousReps == 10)
        // Asking for more slots repeats it ("Like your last set") without claiming it was done there.
        let wider = store.autoFilledEntry(for: exercise, setCount: 3)
        #expect(wider.sets[1].weightKg == 55)
        #expect(wider.sets[1].previousWeightKg == nil)
        store.discard(session: second)
    }
}

/// Regressions from the "life of a workout" review. Every assertion reads back from the
/// **store**, never from the `WorkoutSession` object — asserting on the session is exactly the
/// blind spot that hid the in-place-swap bug for as long as it did.
@MainActor
@Suite("Life of a workout — persisted behaviour")
struct WorkoutLifecycleFixTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func bench(_ store: WorkoutStore) -> ExerciseInfo {
        store.createCustomExercise(
            name: "Barbell Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
    }

    /// One exercise, `sets` planned working sets at 80 × 8, under a linear rule.
    private func makeRoutine(
        _ store: WorkoutStore, exerciseID: UUID, sets: Int = 1, warmups: Int = 0,
        rule: ProgressionRule? = nil
    ) -> UUID {
        let planned = Array(repeating: PlannedSetDraft(kind: .warmup, targetReps: 5), count: warmups)
            + Array(
                repeating: PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80), count: sets
            )
        return store.saveRoutine(
            id: nil, name: "Push A", rule: rule,
            exercises: [RoutineExerciseDraft(exerciseID: exerciseID, sets: planned)]
        ).id
    }

    // MARK: 1 — an in-place swap must re-point the persisted row

    @Test("swapping an exercise in place credits the sets to the new exercise in the store")
    func inPlaceSwapPersistsTheNewExercise() throws {
        let store = try makeStore()
        let barbell = bench(store)
        let dumbbell = store.createCustomExercise(
            name: "Dumbbell Press", primary: [.chest], equipment: "Dumbbell", style: .weightReps
        )
        let routineID = makeRoutine(store, exerciseID: barbell.id, sets: 3)

        let session = store.startWorkout(routineID: routineID)
        let entryID = session.exercises[0].id
        session.replaceInPlace(entryID: entryID, with: dumbbell)
        for index in 0..<3 {
            session.exercises[0].sets[index].weightKg = 30
            session.exercises[0].sets[index].reps = 10
            session.exercises[0].sets[index].isDone = true
        }
        let workoutID = try #require(session.workoutID)
        _ = store.finish(session: session)

        // The persisted row, not the session object.
        let detail = store.workoutDetail(id: workoutID)
        #expect(detail.exercises.map(\.exercise.name) == [dumbbell.name])
        // …and everything downstream that reads the model agrees.
        #expect(store.lastSessions(exerciseID: dumbbell.id) == ["30 × 10,10,10"])
        #expect(store.lastSessions(exerciseID: barbell.id).isEmpty)
        #expect(store.exerciseHistory(exerciseID: barbell.id).isEmpty)
    }

    // MARK: 2 — the launch purge must never destroy logged work

    @Test("purge auto-finishes an old unfinished workout that has sets, and deletes only empty ones")
    func purgeKeepsLoggedWork() throws {
        let store = try makeStore()
        let routineID = makeRoutine(store, exerciseID: bench(store).id)

        let logged = store.startWorkout(routineID: routineID)
        logged.exercises[0].sets[0].isDone = true
        store.sync(session: logged)
        let loggedID = try #require(logged.workoutID)
        let empty = try #require(store.startFreestyle().workoutID)

        // Both were started two days ago.
        let twoDaysAgo = Date().addingTimeInterval(-48 * 60 * 60)
        for id in [loggedID, empty] { store.workout(id: id)?.startedAt = twoDaysAgo }
        store.save()

        store.purgeUnfinished(olderThan: Date().addingTimeInterval(-24 * 60 * 60))

        let survivor = try #require(store.workout(id: loggedID))
        #expect(survivor.endedAt != nil, "a workout with completed sets is finished, never deleted")
        #expect(store.history().contains { $0.id == loggedID })
        #expect(store.workout(id: empty) == nil, "an empty shell is still cleared out")
    }

    // MARK: 3 — a backfill is not finished until it is finished

    @Test("an abandoned backfill never reaches history, and finishing it twice runs once")
    func backfillIsNotFinishedUntilFinish() throws {
        let store = try makeStore()
        let routineID = makeRoutine(store, exerciseID: bench(store).id)
        let date = Date().addingTimeInterval(-60 * 60 * 24 * 5)

        let abandoned = store.startBackfill(date: date, durationMinutes: 45, routineID: routineID)
        abandoned.exercises[0].sets[0].isDone = true
        store.sync(session: abandoned)
        #expect(store.history().isEmpty, "an in-progress backfill is not history")
        #expect(store.lifetimeStats().workouts == 0)
        #expect(store.unfinishedWorkouts().count == 1)

        _ = store.finish(session: abandoned)
        let workoutID = try #require(abandoned.workoutID)
        let endedAt = try #require(store.workout(id: workoutID)?.endedAt)
        #expect(abs(endedAt.timeIntervalSince(date.addingTimeInterval(45 * 60))) < 1)

        // A double tap must not re-finish it.
        _ = store.finish(session: abandoned)
        #expect(store.workout(id: workoutID)?.endedAt == endedAt)
        #expect(store.history().count == 1)
    }

    // MARK: 4 — a backfill's sets are dated inside the backfill

    @Test("backfilled sets are stamped inside [startedAt, endedAt], not today")
    func backfilledSetsAreDatedInThePast() throws {
        let store = try makeStore()
        let routineID = makeRoutine(store, exerciseID: bench(store).id)
        let date = Date().addingTimeInterval(-60 * 60 * 24 * 20)

        let session = store.startBackfill(date: date, durationMinutes: 60, routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        let workoutID = try #require(session.workoutID)
        let workout = try #require(store.workout(id: workoutID))
        let endedAt = try #require(workout.endedAt)
        let stamps = (workout.exercises ?? []).flatMap { $0.sets ?? [] }.compactMap(\.completedAt)
        #expect(stamps.count == 1)
        #expect(stamps.allSatisfy { $0 >= workout.startedAt && $0 <= endedAt })
        // A 20-day-old session must not read as fatigue incurred today.
        #expect(store.recoveryEvents(since: Date().addingTimeInterval(-60 * 60 * 24 * 7)).isEmpty)
    }

    // MARK: 5 — drop sets are not judged as working sets

    @Test("a drop set between working sets doesn't make a hit session read as a miss")
    func dropSetDoesNotCountAsAMissedWorkingSet() throws {
        let store = try makeStore()
        let exercise = bench(store)
        let routineID = makeRoutine(
            store, exerciseID: exercise.id, sets: 3, rule: .linear(incrementKg: 2.5)
        )

        let session = store.startWorkout(routineID: routineID)
        for index in 0..<3 {
            session.exercises[0].sets[index].weightKg = 80
            session.exercises[0].sets[index].reps = 8
        }
        // A drop set logged directly under set 1, exactly as `insertSet` puts it.
        session.exercises[0].sets.insert(
            SetEntry(kind: .drop, weightKg: 64, reps: 6), at: 1
        )
        for index in session.exercises[0].sets.indices { session.exercises[0].sets[index].isDone = true }
        _ = store.finish(session: session)

        // Read back through the store: the next session's prescription, and the persisted stall.
        let next = store.startWorkout(routineID: routineID)
        #expect(next.exercises[0].sets[0].weightKg == 82.5, "every planned set was hit — add weight")
        let routine = try #require(store.fetchRoutineModel(id: routineID))
        let slot = try #require((routine.exercises ?? []).first)
        #expect(slot.stallStateValue.consecutiveMisses == 0)
        store.discard(session: next)
    }

    // MARK: 6 — a skipped exercise's note survives

    @Test("finishing keeps the note from an exercise that was skipped")
    func skippedExerciseNoteSurvives() throws {
        let store = try makeStore()
        let press = bench(store)
        let raise = store.createCustomExercise(
            name: "Lateral Raise", primary: [.delts], equipment: "Dumbbell", style: .weightReps
        )
        let routineID = store.saveRoutine(
            id: nil, name: "Push A",
            exercises: [
                RoutineExerciseDraft(
                    exerciseID: press.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8)]
                ),
                RoutineExerciseDraft(
                    exerciseID: raise.id, sets: [PlannedSetDraft(kind: .working, targetReps: 12)]
                )
            ]
        ).id

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        session.exercises[1].note = "left shoulder pinching"
        let workoutID = try #require(session.workoutID)
        _ = store.finish(session: session)

        let notes = try #require(store.workout(id: workoutID)?.notes)
        #expect(notes.contains("left shoulder pinching"))
        #expect(notes.contains(raise.name))
        #expect(store.workoutDetail(id: workoutID).exercises.count == 1)
    }

    // MARK: 6 — an overnight session doesn't become a 14-hour workout

    @Test("a session finished the next morning is capped, not stamped 14 hours long")
    func overnightSessionIsCapped() throws {
        let store = try makeStore()
        let routineID = makeRoutine(store, exerciseID: bench(store).id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        store.sync(session: session)
        let workoutID = try #require(session.workoutID)
        // Yesterday evening: started 14 hours ago, last set logged 13.5 hours ago.
        let workout = try #require(store.workout(id: workoutID))
        workout.startedAt = Date().addingTimeInterval(-14 * 60 * 60)
        for setModel in (workout.exercises ?? []).flatMap({ $0.sets ?? [] }) {
            setModel.completedAt = Date().addingTimeInterval(-13 * 60 * 60 - 30 * 60)
        }
        store.save()

        let summary = store.finish(session: session)
        #expect(summary.durationSeconds <= TrainingConstants.coachDriftMaxSessionSeconds)
        #expect(store.history().first?.durationMinutes ?? 0 <= 4 * 60)
    }

    // MARK: 6 — deleting a workout takes its badges and its stall with it

    @Test("deleting a workout removes the milestones it earned, and undo puts them back")
    func deleteRevertsMilestones() throws {
        let store = try makeStore()
        let routineID = makeRoutine(store, exerciseID: bench(store).id)

        // Ten sessions: the tenth crosses the bronze "Workout Count" tier.
        var lastWorkoutID: UUID?
        for _ in 0..<10 {
            let session = store.startWorkout(routineID: routineID)
            session.exercises[0].sets[0].isDone = true
            lastWorkoutID = session.workoutID
            _ = store.finish(session: session)
        }
        let workoutID = try #require(lastWorkoutID)
        #expect(store.achievements().contains { $0.milestoneID == "workoutCount" })

        let snapshot = try #require(store.deleteWorkout(id: workoutID))
        #expect(
            !store.achievements().contains { $0.milestoneID == "workoutCount" },
            "a badge must not outlive the workout that earned it"
        )

        store.restoreWorkout(snapshot)
        #expect(store.achievements().contains { $0.milestoneID == "workoutCount" }, "undo is exact")
    }

    @Test("deleting a missed session rolls the miss streak back")
    func deleteRevertsStallState() throws {
        let store = try makeStore()
        let exercise = bench(store)
        let routineID = makeRoutine(
            store, exerciseID: exercise.id, sets: 1, rule: .linear(incrementKg: 2.5)
        )

        // Three sessions at 80: a hit, then two misses.
        var workoutIDs: [UUID] = []
        for reps in [8, 5, 5] {
            let session = store.startWorkout(routineID: routineID)
            session.exercises[0].sets[0].weightKg = 80
            session.exercises[0].sets[0].reps = reps
            session.exercises[0].sets[0].isDone = true
            workoutIDs.append(try #require(session.workoutID))
            _ = store.finish(session: session)
        }

        func misses() throws -> Int {
            let routine = try #require(store.fetchRoutineModel(id: routineID))
            let slot = try #require((routine.exercises ?? []).first)
            return slot.stallStateValue.consecutiveMisses
        }
        let before = try misses()
        #expect(before > 0, "the misses were recorded in the first place")

        let latest = try #require(workoutIDs.last)
        store.deleteWorkout(id: latest)
        #expect(try misses() == before - 1, "a deleted miss is no longer evidence against the lifter")
    }

    // MARK: 6 — resume restores what `sync` doesn't persist

    @Test("resuming restores timed-hold targets, ghosts and the why headline")
    func resumeRestoresSessionState() throws {
        let store = try makeStore()
        let plank = store.createCustomExercise(
            name: "Plank", primary: [.abs], equipment: "Bodyweight", style: .timedHold
        )
        let routineID = store.saveRoutine(
            id: nil, name: "Core", rule: .timed(stepSeconds: 5),
            exercises: [RoutineExerciseDraft(
                exerciseID: plank.id,
                sets: [PlannedSetDraft(kind: .working, targetReps: 1, targetSeconds: 45)]
            )]
        ).id

        // One finished session, so the next one has both a ghost and an engine "why".
        let first = store.startWorkout(routineID: routineID)
        first.exercises[0].sets[0].durationSeconds = 45
        first.exercises[0].sets[0].isDone = true
        _ = store.finish(session: first)

        let second = store.startWorkout(routineID: routineID)
        store.sync(session: second)
        let secondID = try #require(second.workoutID)
        let resumed = try #require(store.resumeSession(for: secondID))

        let set = try #require(resumed.exercises.first?.sets.first)
        #expect(set.targetSeconds != nil, "the hold the timer counts to comes back")
        #expect(set.durationSeconds == nil, "an untouched row was never held")
        #expect(set.previousWeightKg != nil || set.previousReps != nil, "the ghost is rebuilt")
        #expect(resumed.exercises.first?.whyTitle?.isEmpty == false)
        store.discard(session: second)
    }
}
