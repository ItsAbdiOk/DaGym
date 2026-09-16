import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore.recoverySnapshot")
struct WorkoutStoreRecoverySnapshotTests {
    private func makeRoutine(store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 20),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    @Test("3 completed all-out chest sets make chest the most-spent muscle, recovering in the future")
    func chestIsMostSpentWithFutureRecovery() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true // warm-up: contributes nothing
        // RIR 0 → effort 1.0 each, fatigue 3.0 → 33 % spent, just over the 30 % "still spent"
        // line. Three sets of unknown effort (0.75 each) would sit at 27 % — already "fresh",
        // so `recoveredBy` is nil by design (same line `Recovery.headline` uses).
        for index in 1...3 {
            session.exercises[0].sets[index].weightKg = 60
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].effort = Effort(rpe: 10)
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)

        let now = Date()
        let snapshot = store.recoverySnapshot(now: now)

        #expect(snapshot.perMuscle.first?.muscle == .chest)
        let chest = try #require(snapshot.perMuscle.first { $0.muscle == .chest })
        let recoveredBy = try #require(chest.recoveredBy)
        #expect(recoveredBy > now)

        let contributor = try #require(chest.contributors.first)
        #expect(contributor.exerciseName == "Bench Press")
        #expect(contributor.sets == 3)
    }

    @Test("a muscle already under the headline threshold reports no recoveredBy (it's fresh)")
    func underThresholdMuscleIsFreshNow() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        // Three sets with no effort logged: 3 × 0.75 = 2.25 fatigue → 27 % spent < 30 %.
        for index in 1...3 {
            session.exercises[0].sets[index].weightKg = 60
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)

        let chest = try #require(store.recoverySnapshot(now: Date()).perMuscle.first { $0.muscle == .chest })
        #expect(chest.spent < TrainingConstants.recoveryHeadlineThreshold)
        #expect(chest.recoveredBy == nil)
    }

    /// Hand-computed, not re-derived from `Recovery`'s own helpers (the previous version of this
    /// test called `fatigueThreshold` and `recoveredBy` and compared the answer to itself, so it
    /// would have passed whatever those two returned).
    ///
    /// 10 chest sets at RIR 2 → effort 0.75 each → 7.5 set-equivalents, logged now. "Still
    /// spent" is a 0.3 score, and score = f / (6 + f), so the line sits at f = 6 × 0.3 / 0.7 =
    /// 2.5714…. Chest decays with τ = 36 h, so 7.5·e^(−t/36) = 2.5714 → t = 36 · ln(2.9167) ≈
    /// 38.5 h.
    @Test("recoveredBy is when the reading actually crosses the still-spent line")
    func recoveredByCrossesTheStillSpentLine() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let sets = (0..<10).map { _ in PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 80) }
        let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: sets)
        let routineID = store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id

        let session = store.startWorkout(routineID: routineID)
        for index in 0..<10 {
            session.exercises[0].sets[index].weightKg = 80
            session.exercises[0].sets[index].reps = 5
            session.exercises[0].sets[index].effort = Effort(rpe: 8) // RIR 2
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)

        let now = Date()
        let snapshot = store.recoverySnapshot(now: now)
        let chest = try #require(snapshot.perMuscle.first { $0.muscle == .chest })
        let recoveredBy = try #require(chest.recoveredBy)

        #expect(abs(chest.fatigue - 7.5) < 0.01)
        let expectedHours = 36.0 * log(7.5 / 2.571_428_571_4)
        #expect(abs(expectedHours - 38.54) < 0.05, "sanity: the hand arithmetic above")
        #expect(abs(recoveredBy.timeIntervalSince(now) / 3600 - expectedHours) < 0.05)
    }

    /// Finding 3: Home built its own 7-day slice with the training calendar while this screen
    /// used 14 days and `Calendar.current`, so the same muscle showed two different numbers on
    /// two screens (and the Recovery screen's copy claimed a third window).
    @Test("Home and the Recovery snapshot report the same number for the same events")
    func homeAndRecoveryAgree() throws {
        let store = try makeStore()
        let defaults = UserDefaults(suiteName: #function) ?? .standard
        defaults.removePersistentDomain(forName: #function)
        let preferences = Preferences(suite: defaults)
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        // Two sessions: one inside everyone's window, one only inside a 14-day one.
        for daysAgo in [0.2, 9.0] {
            let session = store.startWorkout(routineID: routineID)
            for index in 1...3 {
                session.exercises[0].sets[index].weightKg = 60
                session.exercises[0].sets[index].reps = 8
                session.exercises[0].sets[index].effort = Effort(rpe: 10)
                session.exercises[0].sets[index].isDone = true
            }
            _ = store.finish(session: session)
            let workoutID = try #require(session.workoutID)
            let workout = try #require(store.fetchWorkoutModel(id: workoutID))
            let date = Date().addingTimeInterval(-daysAgo * 86_400)
            workout.startedAt = date
            workout.endedAt = date.addingTimeInterval(3600)
            for workoutExercise in workout.exercises ?? [] {
                for set in workoutExercise.sets ?? [] { set.completedAt = date }
            }
            store.save()
        }

        let now = Date()
        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        let recovery = store.recoverySnapshot(now: now, calendar: preferences.trainingCalendar)
        #expect(!home.recoveryMap.isEmpty)
        #expect(home.recoveryMap.keys.sorted { $0.rawValue < $1.rawValue }
            == recovery.map.keys.sorted { $0.rawValue < $1.rawValue })
        for (muscle, spent) in home.recoveryMap {
            #expect(abs(spent - (recovery.map[muscle] ?? -1)) < 1e-9, "\(muscle) disagreed")
        }
    }

    @Test("muscles with zero events in the last 7 days are listed as untrained")
    func untrainedMusclesHaveNoEvents() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 60
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let snapshot = store.recoverySnapshot(now: Date())

        #expect(!snapshot.untrainedMuscles.contains(.chest))
        #expect(snapshot.untrainedMuscles.contains(.calves))
        #expect(snapshot.untrainedMuscles.contains(.forearms))
    }
}
