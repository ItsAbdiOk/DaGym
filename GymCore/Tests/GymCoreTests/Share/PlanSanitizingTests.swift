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
    func nonPositiveDrops() throws {
        let exercise = try #require(
            PlanRoutineExercise(
                order: 0, exerciseName: "Plank", restOverrideSeconds: -30,
                sets: [PlanSet(order: 0, kind: "working", targetRepsHigh: -1, targetSeconds: 0)]
            ).sanitised()
        )
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

    // MARK: - Programs

    @Test("an absurd or negative program length is clamped to 1...52 weeks")
    func programWeeksClamped() {
        let long = PlanProgram(id: UUID(), name: "Forever", weeks: 10_000).sanitised(routineIDs: [])
        #expect(long.weeks == PlanLimits.maxProgramWeeks)
        let negative = PlanProgram(id: UUID(), name: "Backwards", weeks: -4).sanitised(routineIDs: [])
        #expect(negative.weeks == 1)
    }

    @Test("programWeeks is reconciled with weeks: out-of-range dropped, missing filled in")
    func programWeeksReconciled() {
        let program = PlanProgram(
            id: UUID(), name: "PPL", weeks: 4,
            programWeeks: [
                PlanProgramWeek(index: 1, kind: "normal"),
                PlanProgramWeek(index: 4, kind: "deload"),
                PlanProgramWeek(index: 99, kind: "normal"),
                PlanProgramWeek(index: -1, kind: "normal"),
                PlanProgramWeek(index: 1, kind: "rest")
            ]
        ).sanitised(routineIDs: [])
        #expect(program.programWeeks.map(\.index) == [1, 2, 3, 4])
        #expect(program.programWeeks[0].kind == "normal")
        #expect(program.programWeeks[3].kind == "deload")
    }

    @Test("an unknown week kind becomes a normal week")
    func unknownWeekKind() {
        let program = PlanProgram(
            id: UUID(), name: "PPL", weeks: 1,
            programWeeks: [PlanProgramWeek(index: 1, kind: "apocalypse")]
        ).sanitised(routineIDs: [])
        #expect(program.programWeeks[0].kind == "normal")
    }

    @Test("a day cycle referencing a routine the file doesn't carry is dropped")
    func danglingRoutineReferenceDropped() {
        let known = UUID()
        let program = PlanProgram(
            id: UUID(), name: "PPL", weeks: 1, routineIDs: [known, UUID(), known]
        ).sanitised(routineIDs: [known])
        #expect(program.routineIDs == [known, known])
    }

    @Test("the document sanitises its program against its own routines")
    func documentSanitisesProgram() {
        let routine = PlanRoutine(id: UUID(), name: "Push")
        let document = PlanDocument(
            exportedAt: Date(timeIntervalSince1970: 0), appVersion: "1.0", routines: [routine],
            program: PlanProgram(
                id: UUID(), name: "PPL", weeks: 999, routineIDs: [routine.id, UUID()]
            )
        ).sanitised()
        #expect(document.program?.weeks == PlanLimits.maxProgramWeeks)
        #expect(document.program?.routineIDs == [routine.id])
    }

    // MARK: - Exercises

    @Test("a nameless exercise is dropped rather than creating an unnamed custom")
    func namelessExerciseDropped() {
        let document = PlanDocument(
            exportedAt: Date(timeIntervalSince1970: 0), appVersion: "1.0",
            exercises: [
                PlanExercise(id: UUID(), name: "   "),
                PlanExercise(id: UUID(), name: "Zercher Squat")
            ]
        ).sanitised()
        #expect(document.exercises.map(\.name) == ["Zercher Squat"])
    }

    @Test("a nameless routine slot is dropped rather than resolving to nothing")
    func namelessSlotDropped() {
        let routine = PlanRoutine(
            id: UUID(), name: "Push",
            exercises: [
                PlanRoutineExercise(order: 0, exerciseName: ""),
                PlanRoutineExercise(order: 1, exerciseName: "Bench Press")
            ]
        ).sanitised()
        #expect(routine.exercises.map(\.exerciseName) == ["Bench Press"])
    }

    @Test("a negative or absurd incrementKg and restSeconds are repaired")
    func exerciseNumbersRepaired() throws {
        let negative = try #require(
            PlanExercise(id: UUID(), name: "Squat", incrementKg: -5, restSeconds: -30).sanitised()
        )
        #expect(negative.incrementKg == 2.5)
        #expect(negative.restSeconds == 0)

        // 0 means "use the app's default rest" and must survive a share as exactly that.
        let defaultRest = try #require(
            PlanExercise(id: UUID(), name: "Squat", incrementKg: 2.5, restSeconds: 0).sanitised()
        )
        #expect(defaultRest.restSeconds == 0)

        let absurd = try #require(
            PlanExercise(
                id: UUID(), name: "Squat", incrementKg: 1_000_000, restSeconds: 999_999
            ).sanitised()
        )
        #expect(absurd.incrementKg == PlanLimits.maxIncrementKg)
        #expect(absurd.restSeconds == PlanLimits.maxRestSeconds)

        let nonFinite = try #require(
            PlanExercise(id: UUID(), name: "Squat", incrementKg: .nan).sanitised()
        )
        #expect(nonFinite.incrementKg == 2.5)
    }

    @Test("unbounded instructions and notes are truncated")
    func unboundedTextTruncated() throws {
        let huge = String(repeating: "x", count: 200_000)
        let exercise = try #require(
            PlanExercise(id: UUID(), name: "Squat", instructions: huge, notes: huge).sanitised()
        )
        #expect(exercise.instructions.count == PlanLimits.maxInstructionsLength)
        #expect(exercise.notes.count == PlanLimits.maxNotesLength)

        let routine = PlanRoutine(id: UUID(), name: huge, notes: huge).sanitised()
        #expect(routine.name.count == PlanLimits.maxNameLength)
        #expect(routine.notes.count == PlanLimits.maxNotesLength)
    }

    @Test("a non-finite target RPE is dropped rather than clamped to a number")
    func nonFiniteRPEDropped() {
        #expect(PlanSet(order: 0, kind: "working", targetRPE: .nan).sanitised().targetRPE == nil)
    }

    @Test("an absurd rest override is capped instead of being written verbatim")
    func absurdRestOverrideCapped() throws {
        let slot = try #require(
            PlanRoutineExercise(
                order: 0, exerciseName: "Plank", restOverrideSeconds: 10_000_000
            ).sanitised()
        )
        #expect(slot.restOverrideSeconds == PlanLimits.maxRestSeconds)
    }
}
