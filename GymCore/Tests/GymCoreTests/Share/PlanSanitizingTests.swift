import Foundation
import Testing

@testable import GymCore

@Suite("PlanDocument.sanitised")
struct PlanSanitizingTests {
    @Test("a hand-edited set's bad numbers are clamped or dropped")
    func setClamps() {
        let set = PlanSet(
            order: 0, kind: "working", targetReps: -3, targetWeightKg: -20, targetRPE: 14
        ).sanitised()
        #expect(set.targetReps == nil)
        #expect(set.targetWeightKg == nil)
        #expect(set.targetRPE == 10)
    }

    @Test("a crossed rep range on a set is swapped back into order")
    func setRepRangeSwap() {
        let set = PlanSet(order: 0, kind: "working", targetReps: 12, targetRepsHigh: 8).sanitised()
        #expect(set.targetReps == 8)
        #expect(set.targetRepsHigh == 12)
    }

    @Test("an unknown set kind becomes working")
    func unknownKind() {
        let set = PlanSet(order: 0, kind: "sprint").sanitised()
        #expect(set.kind == "working")
    }

    @Test("a non-positive rest override, target seconds, or target reps-high is dropped")
    func nonPositiveDrops() {
        let exercise = PlanRoutineExercise(
            order: 0, exerciseName: "Plank", restOverrideSeconds: -30,
            sets: [PlanSet(order: 0, kind: "working", targetRepsHigh: -1, targetSeconds: 0)]
        ).sanitised()
        #expect(exercise.restOverrideSeconds == nil)
        #expect(exercise.sets[0].targetSeconds == nil)
        #expect(exercise.sets[0].targetRepsHigh == nil)
    }

    @Test("a routine's crossed rep range is clamped and swapped into order")
    func routineRepRangeSwap() {
        let routine = PlanRoutine(
            id: UUID(), name: "Legs", repRangeLow: 12, repRangeHigh: 8
        ).sanitised()
        #expect(routine.repRangeLow == 8)
        #expect(routine.repRangeHigh == 12)
    }

    @Test("a superset group left with one surviving member is cleared")
    func orphanSuperset() {
        let slot = PlanRoutineExercise(
            order: 0, exerciseName: "Bench Press", supersetGroup: 1,
            sets: [PlanSet(order: 0, kind: "working", targetReps: 8)]
        )
        let routine = PlanRoutine(id: UUID(), name: "Push", exercises: [slot]).sanitised()
        #expect(routine.exercises[0].supersetGroup == nil)
    }

    @Test("a superset group with two surviving members is kept")
    func realSupersetKept() {
        let first = PlanRoutineExercise(order: 0, exerciseName: "Bench Press", supersetGroup: 1)
        let second = PlanRoutineExercise(order: 1, exerciseName: "Cable Fly", supersetGroup: 1)
        let routine = PlanRoutine(id: UUID(), name: "Push", exercises: [first, second]).sanitised()
        #expect(routine.exercises[0].supersetGroup == 1)
        #expect(routine.exercises[1].supersetGroup == 1)
    }

    @Test("sanitised() sanitises every routine in the document")
    func documentSanitisesAllRoutines() {
        let routine = PlanRoutine(
            id: UUID(), name: "Legs", repRangeLow: 20, repRangeHigh: 1,
            exercises: [PlanRoutineExercise(order: 0, exerciseName: "Squat", restOverrideSeconds: -5)]
        )
        let document = PlanDocument(
            exportedAt: Date(timeIntervalSince1970: 0), appVersion: "1.0", routines: [routine]
        ).sanitised()
        #expect(document.routines[0].repRangeLow == 1)
        #expect(document.routines[0].repRangeHigh == 20)
        #expect(document.routines[0].exercises[0].restOverrideSeconds == nil)
    }
}
