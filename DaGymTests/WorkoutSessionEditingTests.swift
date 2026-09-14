import Foundation
import GymCore
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutSession editing")
struct WorkoutSessionEditingTests {
    private func makeBarbellSession(workingWeightKg: Double) -> WorkoutSession {
        let exercise = ExerciseInfo(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", incrementKg: 2.5, bar: .olympic
        )
        let working = SetEntry(kind: .working, weightKg: workingWeightKg, reps: 5)
        let entry = WorkoutExerciseEntry(exercise: exercise, sets: [working])
        return WorkoutSession(title: "Push", subtitle: "", startedAt: Date(), exercises: [entry])
    }

    @Test("addWarmups generates a barbell ramp before the first working set")
    func generatesWarmupRamp() {
        let session = makeBarbellSession(workingWeightKg: 100)
        session.addWarmups(exerciseID: session.exercises[0].id)

        let sets = session.exercises[0].sets
        #expect(sets.count == 5)
        #expect(sets[0].kind == .warmup && sets[0].weightKg == 20 && sets[0].reps == 10)
        #expect(sets[1].weightKg == 40 && sets[1].reps == 5)
        #expect(sets[2].weightKg == 60 && sets[2].reps == 3)
        #expect(sets[3].weightKg == 80 && sets[3].reps == 2)
        #expect(sets[4].kind == .working && sets[4].weightKg == 100)
    }

    @Test("addWarmups is a no-op once warm-ups already exist")
    func doesNotDuplicateWarmups() {
        let session = makeBarbellSession(workingWeightKg: 100)
        let exerciseID = session.exercises[0].id

        session.addWarmups(exerciseID: exerciseID)
        let countAfterFirst = session.exercises[0].sets.count
        session.addWarmups(exerciseID: exerciseID)

        #expect(session.exercises[0].sets.count == countAfterFirst)
    }

    @Test("removeSet keeps at least one set per exercise")
    func removeSetEnforcesMinimumOne() {
        let session = makeBarbellSession(workingWeightKg: 100)
        let exerciseID = session.exercises[0].id
        let firstSetID = session.exercises[0].sets[0].id

        session.removeSet(exerciseID: exerciseID, setID: firstSetID)
        #expect(session.exercises[0].sets.count == 1)

        let secondSet = SetEntry(kind: .working, weightKg: 90, reps: 5)
        session.exercises[0].sets.append(secondSet)
        session.removeSet(exerciseID: exerciseID, setID: firstSetID)

        #expect(session.exercises[0].sets.count == 1)
        #expect(session.exercises[0].sets[0].id == secondSet.id)
    }

    @Test("changeSetKind updates only the kind")
    func changeSetKindUpdatesKind() {
        let session = makeBarbellSession(workingWeightKg: 100)
        let exerciseID = session.exercises[0].id
        let setID = session.exercises[0].sets[0].id

        session.changeSetKind(exerciseID: exerciseID, setID: setID, to: .drop)

        #expect(session.exercises[0].sets[0].kind == .drop)
        #expect(session.exercises[0].sets[0].weightKg == 100)
    }
}

/// Warm-ups have to be loadable and have to make sense for what the set actually logs.
@MainActor
@Suite("Warm-ups: grid and logging style")
struct WorkoutSessionWarmupTests {
    private func session(_ exercise: ExerciseInfo, workingWeightKg: Double) -> WorkoutSession {
        let working = SetEntry(kind: .working, weightKg: workingWeightKg, reps: 5)
        let entry = WorkoutExerciseEntry(exercise: exercise, sets: [working])
        return WorkoutSession(title: "Push", subtitle: "", startedAt: Date(), exercises: [entry])
    }

    /// A rack with no 1.25 kg plates: 42.5 and 62.5 kg cannot be loaded on it.
    private static let noMicroPlates = [
        PlateStock(weightKg: 25, count: 4), PlateStock(weightKg: 20, count: 4),
        PlateStock(weightKg: 15, count: 2), PlateStock(weightKg: 10, count: 4),
        PlateStock(weightKg: 5, count: 4), PlateStock(weightKg: 2.5, count: 4)
    ]

    @Test("warm-ups land on the rack's own grid, not on the exercise increment")
    func warmupsUsePlateGrid() {
        let exercise = ExerciseInfo(
            name: "Squat", primary: [.quads], equipment: "Barbell", incrementKg: 2.5, bar: .olympic
        )
        let session = session(exercise, workingWeightKg: 105)
        session.warmupGrid = { _ in
            .plates(bar: .olympic, plates: Self.noMicroPlates, collarsKg: 0)
        }
        session.addWarmups(exerciseID: session.exercises[0].id)

        let warmups = session.exercises[0].sets.filter { $0.kind == .warmup }
        #expect(!warmups.isEmpty)
        #expect(!warmups.map(\.weightKg).contains(42.5))
        #expect(!warmups.map(\.weightKg).contains(62.5))
        for set in warmups {
            guard case .exact = PlateCalculator.load(
                target: set.weightKg, bar: .olympic, plates: Self.noMicroPlates
            ) else {
                Issue.record("warm-up at \(set.weightKg) kg cannot be loaded")
                continue
            }
        }
    }

    @Test("an assisted pull-up on a machine gets no warm-ups")
    func assistedGetsNoRamp() {
        let exercise = ExerciseInfo(
            name: "Assisted Pull-up", primary: [.lats], equipment: "Machine", incrementKg: 2.5,
            bar: nil, loggingStyle: .assisted
        )
        #expect(exercise.warmupLoadingStyle == .assisted)
        let session = session(exercise, workingWeightKg: 30)
        session.addWarmups(exerciseID: session.exercises[0].id)
        #expect(!session.exercises[0].sets.contains { $0.kind == .warmup })
    }

    @Test("a timed hold on a barbell gets no rep-based warm-ups")
    func timedGetsNoRamp() {
        let exercise = ExerciseInfo(
            name: "Plank", primary: [.abs], equipment: "Barbell", incrementKg: 2.5, bar: .olympic,
            loggingStyle: .timedHold
        )
        #expect(exercise.warmupLoadingStyle == .timed)
        let session = session(exercise, workingWeightKg: 40)
        session.addWarmups(exerciseID: session.exercises[0].id)
        #expect(!session.exercises[0].sets.contains { $0.kind == .warmup })
    }

    @Test("kettlebells, EZ bars and 'other' get a ramp instead of silently getting none")
    func everyKitKindRamps() {
        for kit in ["kettlebell", "ezBar", "other", "cable", "machine", "dumbbell"] {
            let exercise = ExerciseInfo(
                name: kit, primary: [.chest], equipment: kit, incrementKg: 2.5,
                bar: kit == "ezBar" ? .olympic : nil
            )
            let session = session(exercise, workingWeightKg: 40)
            session.addWarmups(exerciseID: session.exercises[0].id)
            #expect(
                session.exercises[0].sets.contains { $0.kind == .warmup },
                "\(kit) produced no warm-ups"
            )
        }
    }
}

/// Superset rounds, set counting and group hygiene — the session-level half of the
/// "life of a workout" review.
@MainActor
@Suite("WorkoutSession supersets and set counting")
struct WorkoutSessionSupersetFixTests {
    /// `warmups` warm-ups then `working` working sets, for one exercise.
    private func entry(_ name: String, warmups: Int, working: Int, restSeconds: Int) -> WorkoutExerciseEntry {
        let exercise = ExerciseInfo(
            name: name, primary: [.chest], equipment: "Barbell", restSeconds: restSeconds
        )
        // Built one at a time: `Array(repeating:)` would hand every row the same id.
        let sets = (0..<warmups).map { _ in SetEntry(kind: .warmup, weightKg: 40, reps: 5) }
            + (0..<working).map { _ in SetEntry(kind: .working, weightKg: 80, reps: 8) }
        return WorkoutExerciseEntry(exercise: exercise, sets: sets, supersetGroup: 1)
    }

    private func session(_ entries: [WorkoutExerciseEntry]) -> WorkoutSession {
        WorkoutSession(title: "Push", subtitle: "", startedAt: Date(), exercises: entries)
    }

    @Test("a superset round is counted in working sets, so a warm-up never waits on a partner")
    func roundsIgnoreWarmups() {
        // Bench ramps up with two warm-ups; the row has none.
        let workout = session([
            entry("Bench", warmups: 2, working: 3, restSeconds: 120),
            entry("Row", warmups: 0, working: 3, restSeconds: 90)
        ])

        // Bench's warm-up is nobody's business: it takes bench's own rest, not zero.
        #expect(workout.restSeconds(after: 0, set: 0) == 120)
        // Bench's first *working* set (row index 2) is round 0 — the row still owes round 0,
        // so there is no rest yet.
        #expect(workout.round(of: 0, set: 2) == 0)
        #expect(workout.restSeconds(after: 0, set: 2) == 0)
        // Once the row's round 0 is done, the group rests on its longest rest.
        workout.exercises[1].sets[0].isDone = true
        #expect(workout.restSeconds(after: 0, set: 2) == 120)
    }

    @Test("removing a superset partner leaves the survivor ungrouped")
    func removingPartnerDissolvesTheGroup() {
        let workout = session([
            entry("Bench", warmups: 0, working: 3, restSeconds: 120),
            entry("Row", warmups: 0, working: 3, restSeconds: 90)
        ])
        #expect(workout.exercises.allSatisfy { $0.supersetGroup != nil })

        workout.exercises.remove(at: 1)
        workout.normalizeSupersets()

        #expect(workout.exercises[0].supersetGroup == nil)
        // …and the survivor rests on its own timer rather than waiting for a partner.
        #expect(workout.restSeconds(after: 0, set: 0) == 120)
    }

    @Test("the header's set count is working sets, the same count the summary shows")
    func setCountsExcludeWarmups() {
        let workout = session([entry("Bench", warmups: 2, working: 3, restSeconds: 120)])
        workout.exercises[0].sets[0].isDone = true // a warm-up
        workout.exercises[0].sets[2].isDone = true // a working set

        #expect(workout.setsTotal == 3)
        #expect(workout.setsDone == 1)
        // `musclesHit` is weighted by the same sets volume is.
        #expect(workout.musclesHit[.chest] == 1)
    }
}
