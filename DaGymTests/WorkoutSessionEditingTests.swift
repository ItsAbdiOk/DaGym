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
