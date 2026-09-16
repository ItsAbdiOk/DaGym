import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Progression through the path a lifter actually walks: `startWorkout` → log → `finish` →
/// `persistProgression` → `startWorkout` again, asserting the number the next session shows.
///
/// Every other progression suite hand-builds `StallState` and `SessionHistory` and calls
/// `ProgressionEngine.prescribe` directly. That hid an entire class of defect — a deload week or
/// a skipped exercise making the engine judge the same session twice, `perSide` never being
/// passed from the store, a multi-routine day never persisting the appended routine's stall, an
/// approved Coach deload stranding a plan weight for ever — because none of it lives in
/// `prescribe`. It lives in the wiring. So this suite never constructs engine input by hand.
@MainActor
@Suite("WorkoutStore progression — through the real path")
struct WorkoutStoreProgressionPathTests {
    // MARK: - Fixtures

    private struct Lift {
        var routineID: UUID
        var exerciseID: UUID
    }

    /// One routine, one exercise, one working set.
    private func makeLift(
        _ store: WorkoutStore, name: String = "Bench Press", routineName: String = "Push A",
        rule: ProgressionRule = .linear(incrementKg: 2.5),
        style: ExerciseInfo.LoggingStyle = .weightReps, equipment: String = "Barbell",
        isPerSide: Bool = false, sets: Int = 1, targetReps: Int = 8, targetWeightKg: Double? = 80
    ) -> Lift {
        let exercise = store.createCustomExercise(
            name: name, primary: [.chest], equipment: equipment, style: style, isPerSide: isPerSide
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: (0..<sets).map { _ in
                PlannedSetDraft(kind: .working, targetReps: targetReps, targetWeightKg: targetWeightKg)
            }
        )
        let routine = store.saveRoutine(id: nil, name: routineName, rule: rule, exercises: [draft])
        return Lift(routineID: routine.id, exerciseID: exercise.id)
    }

    /// Logs every working row of every exercise at `weightKg`/`reps` and finishes the session.
    @discardableResult
    private func logSession(
        _ store: WorkoutStore, routineID: UUID, weightKg: Double, reps: Int
    ) -> WorkoutSession {
        let session = store.startWorkout(routineID: routineID)
        for exerciseIndex in session.exercises.indices {
            for setIndex in session.exercises[exerciseIndex].sets.indices
            where session.exercises[exerciseIndex].sets[setIndex].kind.countsTowardStats {
                session.exercises[exerciseIndex].sets[setIndex].weightKg = weightKg
                session.exercises[exerciseIndex].sets[setIndex].reps = reps
                session.exercises[exerciseIndex].sets[setIndex].isDone = true
            }
        }
        _ = store.finish(session: session)
        return session
    }

    private func routineExercise(
        _ store: WorkoutStore, _ lift: Lift
    ) throws -> RoutineExerciseModel {
        try #require(store.fetchRoutineModel(id: lift.routineID)?.exercises?.first)
    }

    /// What `startWorkout` would show for the first exercise, without leaving a workout behind.
    private func peek(_ store: WorkoutStore, routineID: UUID) throws -> WorkoutExerciseEntry {
        let session = store.startWorkout(routineID: routineID)
        defer { store.discard(session: session) }
        return try #require(session.exercises.first)
    }

    /// Puts every routine into a planned deload week (`planDeloadWeek`'s week 1).
    private func enterDeloadWeek(_ store: WorkoutStore) {
        store.planDeloadWeek()
    }

    /// Ages the deload program out so its week 2 (normal) is in force again — the same move
    /// `DeloadWeekTests` makes, and the only way back to normal prescriptions.
    private func leaveDeloadWeek(_ store: WorkoutStore) throws {
        let active = try #require(store.activeProgramModel())
        active.startedAt = Calendar.current.date(byAdding: .day, value: -8, to: Date())
        store.save()
    }

    // MARK: - The one-session lag (pinned deliberately)

    /// `finish` commits the judgement `startWorkout` already displayed, which is computed from
    /// the session *before* the one being finished. The persisted counter therefore always lags
    /// reality by one session. This is not a bug and must not be "fixed": persisting at start
    /// would let an abandoned workout burn a stall.
    ///
    /// Everything that reads the persisted counter has to be calibrated against what it can
    /// actually reach — see `TrainingConstants.deloadStallCount` — so the lag is pinned here.
    @Test("the persisted stall counter lags the session just logged by exactly one")
    func persistedStallLagsByOneSession() throws {
        let store = try makeStore()
        let lift = makeLift(store)

        logSession(store, routineID: lift.routineID, weightKg: 80, reps: 6)
        #expect(try routineExercise(store, lift).stallStateValue.consecutiveMisses == 0)

        logSession(store, routineID: lift.routineID, weightKg: 80, reps: 6)
        // Two missed sessions are in the log, but only one of them has been judged.
        #expect(try routineExercise(store, lift).stallStateValue.consecutiveMisses == 1)

        logSession(store, routineID: lift.routineID, weightKg: 80, reps: 6)
        #expect(try routineExercise(store, lift).stallStateValue.consecutiveMisses == 2)

        // …and 2 is the ceiling, because the next judgement is the deload, which zeroes it.
        logSession(store, routineID: lift.routineID, weightKg: 80, reps: 6)
        #expect(try routineExercise(store, lift).stallStateValue.consecutiveMisses == 0)
        #expect(TrainingConstants.deloadStallCount <= 2, "a threshold above 2 can never fire")
    }

    // MARK: - F2: a planned deload week must not make the engine judge a session twice

    /// The worked example from the review: 82.5 × 3 × 5 on linear, 5/5/4 then 5/4/4 — two real
    /// misses — and then a planned deload week. Committing the deload session re-judged the
    /// session the previous finish had already judged, and the next start judged it a third time,
    /// so the lifter was deloaded after two misses instead of three.
    @Test("a planned deload week between sessions never advances the miss count")
    func deloadWeekDoesNotDoubleJudge() throws {
        let store = try makeStore()
        let lift = makeLift(store, rule: .linear(incrementKg: 2.5), sets: 3, targetReps: 5,
                            targetWeightKg: 82.5)

        logSession(store, routineID: lift.routineID, weightKg: 82.5, reps: 5)
        logSession(store, routineID: lift.routineID, weightKg: 82.5, reps: 4)
        logSession(store, routineID: lift.routineID, weightKg: 82.5, reps: 4)
        let beforeDeloadWeek = try routineExercise(store, lift).stallStateValue.consecutiveMisses
        #expect(beforeDeloadWeek == 1)

        enterDeloadWeek(store)
        let deloadSession = store.startWorkout(routineID: lift.routineID)
        #expect(deloadSession.exercises.first?.wasPlannedDeload == true)
        for setIndex in deloadSession.exercises[0].sets.indices {
            deloadSession.exercises[0].sets[setIndex].isDone = true
        }
        _ = store.finish(session: deloadSession)

        // The deload row will never be anyone's baseline, so it must never be judged from.
        #expect(try routineExercise(store, lift).stallStateValue.consecutiveMisses == beforeDeloadWeek)

        try leaveDeloadWeek(store)
        let next = try peek(store, routineID: lift.routineID)
        #expect(next.whyTitle?.contains("Deload") != true, "two real misses must not deload")
        #expect(next.sets.first?.weightKg == 82.5)
    }

    // MARK: - F2: a skipped exercise must not make the engine judge a session twice

    @Test("an exercise skipped in a session never advances its own miss count")
    func skippedExerciseDoesNotDoubleJudge() throws {
        let store = try makeStore()
        let lift = makeLift(store)

        logSession(store, routineID: lift.routineID, weightKg: 80, reps: 6)
        logSession(store, routineID: lift.routineID, weightKg: 80, reps: 6)
        #expect(try routineExercise(store, lift).stallStateValue.consecutiveMisses == 1)

        // Started, the exercise left untouched, finished — a skipped lift on a bad day.
        let skipped = store.startWorkout(routineID: lift.routineID)
        _ = store.finish(session: skipped)
        #expect(try routineExercise(store, lift).stallStateValue.consecutiveMisses == 1)

        let next = try peek(store, routineID: lift.routineID)
        #expect(next.whyTitle?.contains("Deload") != true)
        #expect(next.sets.first?.weightKg == 80)
    }

    // MARK: - F4: perSide reaches the engine from the store

    /// GymCore has always taken `perSide`; the store never passed it, and nothing tested the
    /// store's own call. Every unilateral exercise in the app therefore stepped reps by 1.
    @Test("a per-side exercise steps its rep target by 2 through the store")
    func perSideStepsByTwoThroughTheStore() throws {
        let store = try makeStore()
        let lift = makeLift(
            store, name: "Bulgarian Split Squat", rule: .doubleProgression(low: 8, high: 20, incrementKg: 2),
            equipment: "dumbbell", isPerSide: true, sets: 1, targetReps: 20, targetWeightKg: 10
        )

        logSession(store, routineID: lift.routineID, weightKg: 10, reps: 16)

        let next = try peek(store, routineID: lift.routineID)
        // 17 is what a bilateral exercise would be asked for; per-side totals move two at a time.
        #expect(next.sets.first?.reps == 18)
        #expect(next.sets.first?.weightKg == 10)
    }

    @Test("a per-side rep range with an odd bound is rounded up to even through the store")
    func perSideOddRangeIsEvenedThroughTheStore() throws {
        let store = try makeStore()
        let lift = makeLift(
            store, name: "Single-Arm Row", rule: .doubleProgression(low: 7, high: 13, incrementKg: 2),
            equipment: "dumbbell", isPerSide: true, sets: 1, targetReps: 13, targetWeightKg: 10
        )

        logSession(store, routineID: lift.routineID, weightKg: 10, reps: 13)

        let next = try peek(store, routineID: lift.routineID)
        // The range's top, 13, is odd; per-side totals are even, so 14 is the real top.
        #expect(next.sets.first?.reps == 14)
    }

    // MARK: - F6c: a multi-routine day persists both routines' stalls

    /// `persistProgression` used to fetch only `WorkoutModel.routineID`'s routine, which names
    /// just the first routine of a combined day. Every lift appended from a second routine
    /// accumulated no misses at all, so it could never reach its own deload.
    @Test("a lift logged from an appended routine still accumulates misses and deloads")
    func multiRoutineDayPersistsTheAppendedRoutinesStall() throws {
        let store = try makeStore()
        let first = makeLift(store, name: "Bench Press", routineName: "Push A")
        let second = makeLift(store, name: "Overhead Press", routineName: "Arms")

        // Three combined days, the appended lift missing its target every time.
        for _ in 0..<3 {
            let session = store.startWorkout(routineID: first.routineID)
            store.appendRoutine(id: second.routineID, to: session)
            #expect(session.exercises.count == 2)
            for exerciseIndex in session.exercises.indices {
                session.exercises[exerciseIndex].sets[0].weightKg = 80
                session.exercises[exerciseIndex].sets[0].reps = 6
                session.exercises[exerciseIndex].sets[0].isDone = true
            }
            _ = store.finish(session: session)
        }

        #expect(try routineExercise(store, second).stallStateValue.consecutiveMisses == 2)
        let next = try peek(store, routineID: second.routineID)
        #expect(next.whyTitle?.contains("Deload") == true)
    }

    // MARK: - F6a: the bodyweight ladder climbs to maxSets

    /// Four sessions, sized from the plan's 3 sets. The ask has to climb 3 → 4 → 5 and then hand
    /// off; sized from the plan every time it sat at 4 for ever, so `maxSets` was unreachable and
    /// the harder-variation card never appeared.
    @Test("the bodyweight set ladder climbs past plan + 1 across four sessions")
    func bodyweightLadderClimbsAcrossFourSessions() throws {
        let store = try makeStore()
        let lift = makeLift(
            store, name: "Push-Up", rule: .bodyweight(repCeiling: 15, maxSets: 5),
            style: .bodyweightReps, equipment: "Bodyweight", sets: 3, targetReps: 15,
            targetWeightKg: nil
        )

        var setCounts: [Int] = []
        var titles: [String] = []
        for _ in 0..<4 {
            let session = store.startWorkout(routineID: lift.routineID)
            let entry = try #require(session.exercises.first)
            setCounts.append(entry.sets.filter { $0.kind.countsTowardStats }.count)
            titles.append(entry.whyTitle ?? "")
            for setIndex in session.exercises[0].sets.indices {
                session.exercises[0].sets[setIndex].reps = 15
                session.exercises[0].sets[setIndex].isDone = true
            }
            _ = store.finish(session: session)
        }

        // Session 1 has no history (3, from the plan); then the ladder: 4, 5, and 5 again with
        // the hand-off, because 5 is `maxSets`.
        #expect(setCounts == [3, 4, 5, 5])
        #expect(titles.last == "Try a harder variation")
    }

    // MARK: - F6b: an assisted lift through a planned deload week

    @Test("an assisted lift picks up from its last real session, not from the deload week")
    func assistedLiftResumesAfterADeloadWeek() throws {
        let store = try makeStore()
        let lift = makeLift(
            store, name: "Assisted Pull-Up", rule: .assisted(stepKg: 2.5), style: .assisted,
            equipment: "Machine", sets: 1, targetReps: 8, targetWeightKg: 20
        )

        logSession(store, routineID: lift.routineID, weightKg: 20, reps: 8)
        // One step of assistance removed.
        #expect(try peek(store, routineID: lift.routineID).sets.first?.weightKg == 17.5)
        logSession(store, routineID: lift.routineID, weightKg: 17.5, reps: 8)

        enterDeloadWeek(store)
        let deloadSession = store.startWorkout(routineID: lift.routineID)
        #expect(deloadSession.exercises.first?.wasPlannedDeload == true)
        for setIndex in deloadSession.exercises[0].sets.indices {
            deloadSession.exercises[0].sets[setIndex].reps = 8
            deloadSession.exercises[0].sets[setIndex].isDone = true
        }
        _ = store.finish(session: deloadSession)
        try leaveDeloadWeek(store)

        // The deload week's own numbers are never a baseline: the next real session steps down
        // from the 17.5 kg session, to 15 kg of assistance.
        let next = try peek(store, routineID: lift.routineID)
        #expect(next.sets.first?.weightKg == 15)
        #expect(next.sets.first?.assistanceKg == 15)
    }
}
