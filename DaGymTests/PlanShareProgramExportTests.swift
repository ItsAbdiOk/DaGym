import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// `PlanShareService.exportProgram`: a program's day cycle travels with every routine it names,
/// each routine once, the cycle order intact, and nothing that points back at the sender.
@MainActor
@Suite("Plan share: program export")
struct PlanShareProgramExportTests {
    private func routine(_ store: WorkoutStore, name: String, exercise: ExerciseInfo) -> RoutineInfo {
        store.saveRoutine(
            id: nil, name: name,
            exercises: [RoutineExerciseDraft(
                exerciseID: exercise.id,
                sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
            )]
        )
    }

    private struct Fixture {
        var program: ProgramModel
        var upper: RoutineInfo
        var lower: RoutineInfo
    }

    /// Upper/Lower/Upper cycle with a deload week, the way `applyProgramDraft` builds one.
    private func upperLowerProgram(_ store: WorkoutStore, context: ModelContext) throws -> Fixture {
        let bench = store.createCustomExercise(
            name: "Paused Bench", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let squat = store.createCustomExercise(
            name: "Pin Squat", primary: [.quads], equipment: "barbell", style: .weightReps
        )
        let upper = routine(store, name: "Upper", exercise: bench)
        let lower = routine(store, name: "Lower", exercise: squat)
        let program = ProgramModel(name: "U/L", weeks: 3)
        program.routineIDs = [upper.id, lower.id, upper.id]
        context.insert(program)
        context.insert(ProgramWeekModel(index: 2, kind: "deload", program: program))
        context.insert(ProgramWeekModel(index: 0, kind: "normal", program: program))
        context.insert(ProgramWeekModel(index: 1, kind: "normal", program: program))
        try context.save()
        return Fixture(program: program, upper: upper, lower: lower)
    }

    @Test("a repeated routine is exported once, but the day cycle keeps every repeat in order")
    func dedupesRoutinesButKeepsCycle() throws {
        let (store, context) = try makeStoreAndContext()
        let fixture = try upperLowerProgram(store, context: context)
        let (program, upper, lower) = (fixture.program, fixture.upper, fixture.lower)
        let document = try #require(PlanShareService.exportProgram(id: program.id, context: context))
        let plan = try #require(document.program)

        #expect(Set(document.routines.map(\.name)) == ["Upper", "Lower"])
        #expect(document.routines.count == 2)
        let sharedUpper = PlanShareService.sharedID(for: upper.id)
        let sharedLower = PlanShareService.sharedID(for: lower.id)
        #expect(plan.routineIDs == [sharedUpper, sharedLower, sharedUpper])
        #expect(Set(document.routines.map(\.id)) == [sharedUpper, sharedLower])
        #expect(plan.name == "U/L")
        #expect(plan.weeks == 3)
    }

    @Test("program weeks travel sorted by index, and the sender's ids never leave the store")
    func weeksSortedAndIDsHashed() throws {
        let (store, context) = try makeStoreAndContext()
        let fixture = try upperLowerProgram(store, context: context)
        let (program, upper, lower) = (fixture.program, fixture.upper, fixture.lower)
        let document = try #require(PlanShareService.exportProgram(id: program.id, context: context))
        let plan = try #require(document.program)

        #expect(plan.programWeeks.map(\.index) == [0, 1, 2])
        #expect(plan.programWeeks.map(\.kind) == ["normal", "normal", "deload"])
        #expect(plan.id == PlanShareService.sharedID(for: program.id))
        #expect(plan.id != program.id)
        let localIDs: Set<UUID> = [program.id, upper.id, lower.id]
        #expect(localIDs.isDisjoint(with: plan.routineIDs))
        #expect(localIDs.isDisjoint(with: document.routines.map(\.id)))
        #expect(Set(document.exercises.map(\.name)) == ["Paused Bench", "Pin Squat"])
    }

    @Test("working weights stay home unless the export asks for them")
    func weightsOnlyOnRequest() throws {
        let (store, context) = try makeStoreAndContext()
        let program = try upperLowerProgram(store, context: context).program
        let shared = try #require(PlanShareService.exportProgram(id: program.id, context: context))
        let sharedWeights = shared.routines.flatMap(\.exercises).flatMap(\.sets).compactMap(\.targetWeightKg)
        #expect(sharedWeights.isEmpty)
        let printed = try #require(
            PlanShareService.exportProgram(id: program.id, context: context, includeWeights: true)
        )
        #expect(printed.routines.first?.exercises.first?.sets.first?.targetWeightKg == 60)
    }

    @Test("a routine the program names but the store no longer has is left out of the cycle")
    func missingRoutineDropsOutOfCycle() throws {
        let (store, context) = try makeStoreAndContext()
        let fixture = try upperLowerProgram(store, context: context)
        let (program, upper) = (fixture.program, fixture.upper)
        program.routineIDs = [upper.id, UUID(), upper.id]
        try context.save()
        let document = try #require(PlanShareService.exportProgram(id: program.id, context: context))
        let sharedUpper = PlanShareService.sharedID(for: upper.id)
        #expect(document.routines.map(\.id) == [sharedUpper])
        #expect(document.program?.routineIDs == [sharedUpper, sharedUpper])
    }

    @Test("an unknown program id exports nothing")
    func unknownProgram() throws {
        let (_, context) = try makeStoreAndContext()
        #expect(PlanShareService.exportProgram(id: UUID(), context: context) == nil)
    }

    @Test("the exported program imports back as one program over the imported routines")
    func roundTripsThroughImport() throws {
        let (store, context) = try makeStoreAndContext()
        let program = try upperLowerProgram(store, context: context).program
        let document = try #require(PlanShareService.exportProgram(id: program.id, context: context))
        let decoded = try PlanCodec.decode(PlanCodec.encode(document))

        let destination = try makeContext()
        let report = PlanShareService.importPlan(document: decoded, context: destination)
        #expect(report.routinesImported == 2)
        #expect(report.programImported)
        let imported = try #require(try destination.fetch(FetchDescriptor<ProgramModel>()).first)
        #expect(imported.name == "U/L")
        #expect(imported.routineIDs.count == 3)
        #expect(imported.routineIDs[0] == imported.routineIDs[2])
        #expect(imported.routineIDs[0] != imported.routineIDs[1])
        #expect((imported.programWeeks ?? []).count == 3)
    }
}
