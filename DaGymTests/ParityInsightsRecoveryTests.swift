import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// OpenGym parity (insights recs 2–3): 14-day scan with a causal per-muscle reference, and the
/// graded strength-retention list in the recovery snapshot.
@MainActor
@Suite("Parity: recovery snapshot")
struct ParityInsightsRecoveryTests {
    private let now = Date()

    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(store: WorkoutStore, exerciseID: UUID, sets: Int) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: (0..<sets).map { _ in PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60) }
        )
        return store.saveRoutine(id: nil, name: "Day", exercises: [draft]).id
    }

    /// Logs every planned set at RIR 0 and backdates the workout to `daysAgo`.
    @discardableResult
    private func logSession(_ store: WorkoutStore, routineID: UUID, daysAgo: Double) throws -> UUID {
        let session = store.startWorkout(routineID: routineID)
        for index in session.exercises[0].sets.indices {
            session.exercises[0].sets[index].weightKg = 60
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].effort = Effort(rpe: 10)
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)
        let workoutID = try #require(session.workoutID)
        let workout = try #require(store.fetchWorkoutModel(id: workoutID))
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        workout.startedAt = date
        workout.endedAt = date.addingTimeInterval(3600)
        for exercise in workout.exercises ?? [] {
            for set in exercise.sets ?? [] { set.completedAt = date }
        }
        store.save()
        return workoutID
    }

    @Test("the scan covers 14 days: a 10-day-old leg day still shows on the map")
    func scanCoversFourteenDays() throws {
        let store = try makeStore()
        let squat = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: squat.id, sets: 12)
        try logSession(store, routineID: routineID, daysAgo: 10)

        let snapshot = store.recoverySnapshot(now: now)
        #expect(snapshot.map[.quads] != nil)
        #expect(snapshot.perMuscle.contains { $0.muscle == .quads })
        // …but "untrained" still means the last 7 days.
        #expect(snapshot.untrainedMuscles.contains(.quads))
    }

    @Test("deleting the middle of three chest sessions never raises chest fatigue")
    func deletingASessionNeverRaisesFatigue() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let small = makeRoutine(store: store, exerciseID: bench.id, sets: 3)
        let big = makeRoutine(store: store, exerciseID: bench.id, sets: 12)
        try logSession(store, routineID: small, daysAgo: 8)
        let middle = try logSession(store, routineID: small, daysAgo: 4)
        try logSession(store, routineID: big, daysAgo: 0.1)

        let before = try #require(store.recoverySnapshot(now: now).perMuscle.first { $0.muscle == .chest })
        store.deleteWorkout(id: middle)
        let after = try #require(store.recoverySnapshot(now: now).perMuscle.first { $0.muscle == .chest })
        #expect(after.fatigue <= before.fatigue)
        #expect(after.spent <= before.spent)
    }

    @Test("a single 3-set biceps session reads the same as the plain decayed sum")
    func singleSessionUnchanged() throws {
        let store = try makeStore()
        let curl = store.createCustomExercise(
            name: "Curl", primary: [.biceps], equipment: "Dumbbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: curl.id, sets: 3)
        try logSession(store, routineID: routineID, daysAgo: 0.5)

        let biceps = try #require(store.recoverySnapshot(now: now).perMuscle.first { $0.muscle == .biceps })
        let expected = 3 * exp(-12.0 / Muscle.biceps.recoveryTimeConstantHours)
        #expect(abs(biceps.fatigue - expected) < 1e-6)
    }

    @Test("retention: 10 days → 1.0, 42 days → floor, never-trained hamstrings after glutes")
    func retentionGraded() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let hipThrust = store.createCustomExercise(
            name: "Hip Thrust", primary: [.glutes], equipment: "Barbell", style: .weightReps
        )
        let benchDay = makeRoutine(store: store, exerciseID: bench.id, sets: 3)
        let gluteDay = makeRoutine(store: store, exerciseID: hipThrust.id, sets: 3)
        try logSession(store, routineID: benchDay, daysAgo: 10)
        try logSession(store, routineID: gluteDay, daysAgo: 42)

        let snapshot = store.recoverySnapshot(now: now)
        #expect(snapshot.retention[.chest] == 1)
        let glutes = try #require(snapshot.retention[.glutes])
        #expect(abs(glutes - TrainingConstants.retentionFloor) < 1e-6)
        #expect(snapshot.retention[.hams] == TrainingConstants.retentionFloor)

        #expect(!snapshot.detrainedMuscles.contains { $0.muscle == .chest })
        let glutesIndex = try #require(snapshot.detrainedMuscles.firstIndex { $0.muscle == .glutes })
        let hamsIndex = try #require(snapshot.detrainedMuscles.firstIndex { $0.muscle == .hams })
        #expect(glutesIndex < hamsIndex)
        #expect(snapshot.detrainedMuscles.first { $0.muscle == .glutes }?.lastTrained != nil)
        #expect(snapshot.detrainedMuscles.first { $0.muscle == .hams }?.lastTrained == nil)
    }

    @Test("retention orders 3 weeks off above 8 days off")
    func retentionOrdersByTimeOff() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let row = store.createCustomExercise(
            name: "Row", primary: [.lats], equipment: "Barbell", style: .weightReps
        )
        let benchDay = makeRoutine(store: store, exerciseID: bench.id, sets: 3)
        let rowDay = makeRoutine(store: store, exerciseID: row.id, sets: 3)
        try logSession(store, routineID: benchDay, daysAgo: 21)
        try logSession(store, routineID: rowDay, daysAgo: 18)

        let detrained = store.recoverySnapshot(now: now).detrainedMuscles
        let chestIndex = try #require(detrained.firstIndex { $0.muscle == .chest })
        let latsIndex = try #require(detrained.firstIndex { $0.muscle == .lats })
        #expect(chestIndex < latsIndex)
        let chest = detrained[chestIndex].retention
        let lats = detrained[latsIndex].retention
        #expect(chest < lats)
        #expect(lats < 1)
    }
}
