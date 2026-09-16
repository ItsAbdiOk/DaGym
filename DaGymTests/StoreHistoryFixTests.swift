import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore sessions, history and PR log")
struct StoreHistoryFixTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A single working-set routine, optionally under a progression rule.
    private func makeRoutine(
        _ store: WorkoutStore, exerciseID: UUID, rule: ProgressionRule? = nil, targetWeightKg: Double? = 80
    ) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: targetWeightKg)]
        )
        return store.saveRoutine(id: nil, name: "Push A", rule: rule, exercises: [draft]).id
    }

    private func makeBench(_ store: WorkoutStore) -> ExerciseInfo {
        store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
    }

    /// Completes and finishes one session at `weightKg` × `reps` on the routine's only set.
    @discardableResult
    private func logSession(
        _ store: WorkoutStore, routineID: UUID, weightKg: Double, reps: Int
    ) -> (summary: WorkoutSummary, workoutID: UUID?) {
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].weightKg = weightKg
        session.exercises[0].sets[0].reps = reps
        session.exercises[0].sets[0].isDone = true
        return (store.finish(session: session), session.workoutID)
    }

    // MARK: - D1 backfill end date

    @Test("finishing a backfill keeps date + duration as its end and Health gets that window")
    func backfillKeepsPlannedEndDate() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthWriteWorkouts = true
        let health = FakeHealthStore()
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)
        let routineID = makeRoutine(store, exerciseID: makeBench(store).id)

        let date = Date().addingTimeInterval(-60 * 60 * 24 * 30)
        let session = store.startBackfill(date: date, durationMinutes: 60, routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        let summary = store.finish(session: session)

        let workoutID = try #require(session.workoutID)
        let workout = try #require(store.workout(id: workoutID))
        let plannedEnd = date.addingTimeInterval(60 * 60)
        #expect(abs(try #require(workout.endedAt).timeIntervalSince(plannedEnd)) < 1)
        #expect(summary.durationSeconds == 60 * 60)
        #expect(store.history().first?.durationMinutes == 60)

        await service.syncFinishedWorkout(workout)
        let saved = await health.savedWorkouts
        #expect(saved.count == 1)
        let input = try #require(saved.first)
        #expect(abs(input.start.timeIntervalSince(date)) < 1)
        #expect(abs(input.end.timeIntervalSince(plannedEnd)) < 1)
    }

    // MARK: - D10 finish idempotence

    @Test("finishing the same session twice burns one stall, not two")
    func finishTwiceBurnsOneStall() throws {
        let store = try makeStore()
        let bench = makeBench(store)
        let routineID = makeRoutine(store, exerciseID: bench.id, rule: .linear(incrementKg: 2.5))
        logSession(store, routineID: routineID, weightKg: 80, reps: 8)
        // Each finish commits the judgement of the session *before* it, so this miss lands in
        // the stall state when the next session finishes.
        logSession(store, routineID: routineID, weightKg: 80, reps: 3)

        let missed = store.startWorkout(routineID: routineID)
        missed.exercises[0].sets[0].reps = 3
        missed.exercises[0].sets[0].isDone = true
        let first = store.finish(session: missed)
        let firstEnd = store.workout(id: try #require(missed.workoutID))?.endedAt
        let second = store.finish(session: missed)

        let routineExercise = try #require(store.fetchRoutineModel(id: routineID)?.exercises?.first)
        #expect(routineExercise.stallStateValue.consecutiveMisses == 1)
        #expect(store.workout(id: try #require(missed.workoutID))?.endedAt == firstEnd)
        #expect(store.history().count == 3)
        #expect(second.setsDone == first.setsDone)
        #expect(second.prs.isEmpty)
    }

    // MARK: - D5 warm-ups keep their own weight

    @Test("session 2 of a warm-up + working plan keeps the 40 kg warm-up while the working weight moves")
    func warmUpsAreNotPrescribedAtWorkingWeight() throws {
        let store = try makeStore()
        let bench = makeBench(store)
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .warmup, targetReps: 5, targetWeightKg: 60),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)
            ]
        )
        let routineID = store.saveRoutine(
            id: nil, name: "Push A", rule: .linear(incrementKg: 2.5), exercises: [draft]
        ).id

        let first = store.startWorkout(routineID: routineID)
        for index in first.exercises[0].sets.indices {
            first.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: first)

        let second = store.startWorkout(routineID: routineID)
        let sets = second.exercises[0].sets
        #expect(sets.count == 5)
        #expect(sets[0].kind == .warmup)
        #expect(sets[0].weightKg == 40)
        #expect(sets[0].reps == 10)
        #expect(sets[1].weightKg == 60)
        #expect(sets[1].reps == 5)
        #expect(sets[2].kind == .working)
        #expect(sets[2].weightKg == 82.5)
        #expect(sets[4].weightKg == 82.5)
        #expect(second.exercises[0].whyTitle == "+2.5 kg")
    }

    // MARK: - D6 bodyweight "+1 set" reaches the row

    @Test("a bodyweight +1 set prescription adds a fourth row")
    func bodyweightExtraSetIsAppended() throws {
        let store = try makeStore()
        let pullups = store.createCustomExercise(
            name: "Pull-Up", primary: [.lats], equipment: "Bodyweight", style: .bodyweightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: pullups.id,
            sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8) },
            overrideRule: .bodyweight(repCeiling: 10, maxSets: 5)
        )
        let routineID = store.saveRoutine(id: nil, name: "Pull B", exercises: [draft]).id

        let first = store.startWorkout(routineID: routineID)
        for index in first.exercises[0].sets.indices {
            first.exercises[0].sets[index].reps = 10
            first.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: first)

        let second = store.startWorkout(routineID: routineID)
        #expect(second.exercises[0].whyTitle == "+1 set")
        #expect(second.exercises[0].sets.count == 4)
        // The extra set comes with reps back at the plan's base (8), not the ceiling just hit.
        #expect(second.exercises[0].sets.allSatisfy { $0.kind == .working && $0.reps == 8 })
    }

    // MARK: - D8 deleting a workout rebuilds the PR cache

    @Test("deleting the 1,400 kg workout reverts the e1RM PR to the previous best")
    func deletingWorkoutRevertsRecord() throws {
        let store = try makeStore()
        let bench = makeBench(store)
        let routineID = makeRoutine(store, exerciseID: bench.id)
        let (_, realID) = logSession(store, routineID: routineID, weightKg: 100, reps: 5)
        let (typo, typoID) = logSession(store, routineID: routineID, weightKg: 1_400, reps: 5)
        #expect(typo.prs.count == 1)
        #expect(store.bestE1RMRecord(exerciseID: bench.id)?.weightKg == 1_400)

        store.deleteWorkout(id: try #require(typoID))

        let best = try #require(store.bestE1RMRecord(exerciseID: bench.id))
        #expect(best.weightKg == 100)
        #expect(best.reps == 5)
        #expect(best.workoutID == realID)
        #expect(store.prCount(for: try #require(realID)) == 1)
        #expect(store.history().count == 1)

        // The next real record is judged against 100 kg again, not the deleted 1,400 kg.
        let comeback = logSession(store, routineID: routineID, weightKg: 105, reps: 5)
        #expect(comeback.summary.prs.count == 1)
    }

    // MARK: - D7 PR counts don't decay

    @Test("a workout's PR count survives a later PR on the same exercise")
    func prCountIsStableAfterLaterRecord() throws {
        let store = try makeStore()
        let bench = makeBench(store)
        let routineID = makeRoutine(store, exerciseID: bench.id)
        let (_, firstID) = logSession(store, routineID: routineID, weightKg: 80, reps: 8)
        #expect(store.history().first { $0.id == firstID }?.prCount == 1)

        let (_, secondID) = logSession(store, routineID: routineID, weightKg: 90, reps: 8)
        let rows = store.history()
        #expect(rows.first { $0.id == firstID }?.prCount == 1)
        #expect(rows.first { $0.id == secondID }?.prCount == 1)
        #expect(store.workoutDetail(id: try #require(firstID)).prCount == 1)

        // Rebuilding from history gives the same answer as the live log.
        store.rebuildPersonalRecords()
        #expect(store.prCount(for: try #require(firstID)) == 1)
        #expect(store.prCount(for: try #require(secondID)) == 1)
        #expect(store.bestE1RMRecord(exerciseID: bench.id)?.weightKg == 90)
    }

    // MARK: - D12 one definition of "sets"

    @Test("History row, detail, summary and weekly recap agree on the set count")
    func setCountsAgree() throws {
        let store = try makeStore()
        let bench = makeBench(store)
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)
            ]
        )
        let routineID = store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
        let session = store.startWorkout(routineID: routineID)
        for index in session.exercises[0].sets.indices {
            session.exercises[0].sets[index].isDone = true
        }
        let summary = store.finish(session: session)
        let workoutID = try #require(session.workoutID)

        let recap = store.weeklyRecap(weeklyGoal: 4)
        #expect(recap.sets == 2)
        #expect(store.history().first?.sets == 2)
        #expect(store.workoutDetail(id: workoutID).setsDone == 2)
        #expect(summary.setsDone == 2)
    }

    // MARK: - D13 unfinished workouts

    @Test("unfinished workouts are listed newest first, purged by age, and resumable with their sets")
    func unfinishedWorkoutsAreRecoverable() throws {
        let store = try makeStore()
        let bench = makeBench(store)
        let routineID = makeRoutine(store, exerciseID: bench.id)
        logSession(store, routineID: routineID, weightKg: 80, reps: 8)

        let stale = store.startWorkout(routineID: routineID)
        let staleID = try #require(stale.workoutID)
        let staleModel = try #require(store.workout(id: staleID))
        staleModel.startedAt = Date().addingTimeInterval(-60 * 60 * 48)
        store.save()

        let live = store.startWorkout(routineID: routineID)
        live.exercises[0].sets[0].weightKg = 82.5
        live.exercises[0].sets[0].isDone = true
        live.notes = "left off here"
        store.sync(session: live)
        let liveID = try #require(live.workoutID)

        let unfinished = store.unfinishedWorkouts()
        #expect(unfinished.map(\.id) == [liveID, staleID])
        #expect(store.history().count == 1)

        #expect(store.purgeUnfinished(olderThan: Date().addingTimeInterval(-60 * 60 * 24)) == 1)
        #expect(store.unfinishedWorkouts().map(\.id) == [liveID])
        #expect(store.workout(id: staleID) == nil)

        let resumed = try #require(store.resumeSession(for: liveID))
        #expect(resumed.workoutID == liveID)
        #expect(resumed.title == live.title)
        #expect(resumed.notes == "left off here")
        #expect(resumed.exercises.count == 1)
        #expect(resumed.exercises[0].exercise.id == bench.id)
        #expect(resumed.exercises[0].sets.count == 1)
        #expect(resumed.exercises[0].sets[0].weightKg == 82.5)
        #expect(resumed.exercises[0].sets[0].isDone)
        #expect(resumed.exercises[0].lastSessions == ["80 × 8"])

        _ = store.finish(session: resumed)
        #expect(store.unfinishedWorkouts().isEmpty)
        #expect(store.resumeSession(for: liveID) == nil)
        #expect(store.history().count == 2)
    }

    // MARK: - D22 the card's history strip is filled

    @Test("a store-built entry carries the last-sessions strip and sparkline")
    func entriesCarryHistoryStrip() throws {
        let store = try makeStore()
        let bench = makeBench(store)
        let routineID = makeRoutine(store, exerciseID: bench.id)
        logSession(store, routineID: routineID, weightKg: 80, reps: 8)
        logSession(store, routineID: routineID, weightKg: 82.5, reps: 8)

        let next = store.startWorkout(routineID: routineID)
        #expect(next.exercises[0].lastSessions == ["82.5 × 8", "80 × 8"])
        #expect(next.exercises[0].sparkline.count == 2)
        #expect(next.exercises[0].sparkline == next.exercises[0].sparkline.sorted())

        let added = store.autoFilledEntry(for: bench)
        #expect(added.lastSessions == ["82.5 × 8", "80 × 8"])
        #expect(added.sparkline.count == 2)
    }
}
