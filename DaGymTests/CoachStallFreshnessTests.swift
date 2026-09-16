import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// `CoachLiftSnapshot.stallState` must be the engine's judgement of *current* history, not the
/// persisted `stallStateValue`, which `finish` writes one session behind (see
/// `WorkoutStore+Coach.swift` `currentStallState`). Fed the persisted copy, a lift that had just
/// hit cleanly was carded as stalled — with the engine's next prescription an increase — and
/// approving the card deloaded the lifter off that increase.
@MainActor
@Suite("WorkoutStore coach adapter: stall state freshness")
struct CoachStallFreshnessTests {
    /// A one-exercise linear routine at 80 kg × 8, +2.5 kg.
    private func benchRoutine(_ store: WorkoutStore) -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let workingSet = PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)
        let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: [workingSet])
        return store.saveRoutine(
            id: nil, name: "Bench", rule: .linear(incrementKg: 2.5), exercises: [draft]
        )
    }

    /// Logs one real session through `startWorkout`/`finish`, so `persistProgression` writes
    /// the (lagging) stall state exactly as it does in the app.
    private func logSession(_ store: WorkoutStore, routineID: UUID, weightKg: Double = 80, reps: Int) {
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].weightKg = weightKg
        session.exercises[0].sets[0].reps = reps
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
    }

    private func persistedMisses(_ store: WorkoutStore, routineID: UUID) throws -> Int {
        let routineModel = try #require(store.fetchRoutineModel(id: routineID))
        return try #require(routineModel.exercises?.first).stallStateValue.consecutiveMisses
    }

    @Test("a clean hit after two misses is not carded, even though the persisted counter lags")
    func cleanHitClearsTheCardDespiteTheLag() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        logSession(store, routineID: routine.id, reps: 6) // first time: nothing judged
        logSession(store, routineID: routine.id, reps: 6) // judges session 1 → 1
        logSession(store, routineID: routine.id, reps: 8) // judges session 2 → 2; the hit is unjudged

        // The lag is real: the store still says two misses.
        #expect(try persistedMisses(store, routineID: routine.id) == 2)
        // The coach sees the hit: no streak, no card.
        let lift = try #require(store.coachInput().lifts.first { $0.name == "Bench Press" })
        #expect(lift.stallState.consecutiveMisses == 0)
        #expect(!store.coachCards().contains { $0.rule == .stalledLift })
        // And it agrees with what the lifter is about to be prescribed.
        let next = store.startWorkout(routineID: routine.id)
        #expect(next.exercises[0].sets[0].weightKg == 82.5)
    }

    @Test("a hand-edited drop to a lighter weight is judged fresh, not carded at the old weight")
    func movingOffTheStalledWeightIsJudgedFresh() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        logSession(store, routineID: routine.id, reps: 6)
        logSession(store, routineID: routine.id, reps: 6)
        logSession(store, routineID: routine.id, weightKg: 70, reps: 8)

        // Persisted: two misses at 80. Fresh: the weight changed, the streak reset, and 70 was a hit.
        #expect(try persistedMisses(store, routineID: routine.id) == 2)
        let lift = try #require(store.coachInput().lifts.first { $0.name == "Bench Press" })
        #expect(lift.stallState.consecutiveMisses == 0)
        #expect(!store.coachCards().contains { $0.rule == .stalledLift })
    }

    @Test("two real misses in a row are carded, with the count the sessions actually add up to")
    func twoRealMissesAreCarded() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        logSession(store, routineID: routine.id, reps: 6)
        logSession(store, routineID: routine.id, reps: 6)

        // Persisted says 1 (session 2 unjudged); the coach counts both.
        #expect(try persistedMisses(store, routineID: routine.id) == 1)
        let lift = try #require(store.coachInput().lifts.first { $0.name == "Bench Press" })
        #expect(lift.stallState.consecutiveMisses == 2)
        let card = try #require(store.coachCards().first { $0.rule == .stalledLift })
        #expect(card.body.contains("2 sessions in a row"))
    }
}
