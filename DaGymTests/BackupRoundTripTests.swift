import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Backup round trip")
struct BackupRoundTripTests {
    private func makeStore() throws -> (store: WorkoutStore, context: ModelContext) {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        return (WorkoutStore(context: context), context)
    }

    /// A routine with a routine-level rule and a per-exercise override, engine state on the slot,
    /// one finished workout flagged as a planned deload, a program with weeks, and an achievement.
    private func populate(_ store: WorkoutStore, context: ModelContext) throws -> UUID {
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ],
            overrideRule: .linear(incrementKg: 5)
        )
        let routine = store.saveRoutine(
            id: nil, name: "Push A", rule: .doubleProgression(low: 6, high: 8, incrementKg: 2.5),
            exercises: [draft]
        )
        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        let slot = try #require(routineModel.exercises?.first)

        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[1].weightKg = 60
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)
        // Finishing rewrites the engine memory; the hand-set values below are what export must carry.
        slot.stallJSON = #"{"misses":2}"#
        slot.trainingMaxKg = 100
        let workoutID = try #require(session.workoutID)
        let workout = try #require(store.fetchWorkoutModel(id: workoutID))
        try #require(workout.exercises?.first).wasPlannedDeload = true

        let program = store.createProgram(from: .pushPullLegs)
        store.startProgram(id: program.id)
        context.insert(AchievementModel(milestoneID: "first-workout", tier: "bronze", workoutID: workout.id))
        try context.save()
        return routine.id
    }

    @Test("export → import preserves rule JSON, stall, TM, planned deload, programs and achievements")
    func roundTripPreservesEngineState() throws {
        let (source, sourceContext) = try makeStore()
        let routineID = try populate(source, context: sourceContext)
        let exportedDocument = BackupService.export(context: sourceContext)
        let document = try BackupCodec.decode(BackupCodec.encode(exportedDocument))

        let exported = try #require(document.routines.first { $0.id == routineID })
        #expect(exported.progressionRuleJSON?.isEmpty == false)
        #expect(exported.exercises.first?.progressionRuleJSON?.isEmpty == false)
        #expect(exported.exercises.first?.stallJSON == #"{"misses":2}"#)
        #expect(exported.exercises.first?.trainingMaxKg == 100)
        #expect(document.workouts.first?.exercises.first?.wasPlannedDeload == true)
        #expect(document.workouts.first?.routineID == routineID)
        #expect(document.programs?.count == 1)
        #expect(document.achievements?.count == 1)

        let (destination, destinationContext) = try makeStore()
        let report = BackupService.import(document: document, context: destinationContext)
        #expect(report.problems.isEmpty)

        let routine = try #require(destination.fetchRoutineModel(id: routineID))
        #expect(routine.progressionRuleJSON == exported.progressionRuleJSON)
        let slot = try #require(routine.exercises?.first)
        #expect(slot.progressionRuleJSON == exported.exercises.first?.progressionRuleJSON)
        #expect(slot.stallJSON == #"{"misses":2}"#)
        #expect(slot.trainingMaxKg == 100)
        #expect(destination.effectiveRule(routine: routine, routineExercise: slot) != nil)

        let workout = try #require(try destinationContext.fetch(FetchDescriptor<WorkoutModel>()).first)
        #expect(workout.exercises?.first?.wasPlannedDeload == true)
        #expect(workout.routineID == routineID)

        let programs = try destinationContext.fetch(FetchDescriptor<ProgramModel>())
        #expect(programs.count == 1)
        #expect(programs.first?.isActive == true)
        #expect(programs.first?.programWeeks?.count == StarterPrograms.weekKinds(for: .pushPullLegs).count)
        #expect(try destinationContext.fetchCount(FetchDescriptor<AchievementModel>()) == 1)
    }

    @Test("import rebuilds the PR cache from the imported workouts")
    func importRebuildsPersonalRecords() throws {
        let (source, sourceContext) = try makeStore()
        _ = try populate(source, context: sourceContext)
        let document = BackupService.export(context: sourceContext)

        let (destination, destinationContext) = try makeStore()
        BackupService.import(document: document, context: destinationContext)
        let bench = try #require(destination.exercises(matching: "Bench Press").first)
        #expect(destination.bestE1RMRecord(exerciseID: bench.id) != nil)
        #expect(bench.bestE1RM != nil)
    }

    @Test("importing twice adds no second program or achievement")
    func reimportIsIdempotentForNewTables() throws {
        let (source, sourceContext) = try makeStore()
        _ = try populate(source, context: sourceContext)
        let document = BackupService.export(context: sourceContext)

        let (_, destinationContext) = try makeStore()
        BackupService.import(document: document, context: destinationContext)
        BackupService.import(document: document, context: destinationContext)
        #expect(try destinationContext.fetchCount(FetchDescriptor<ProgramModel>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<AchievementModel>()) == 1)
    }

    @Test("untouched seeded exercises are not exported as overrides; an edited one is")
    func overridesCompareAgainstTheSeed() throws {
        let (store, context) = try makeStore()
        ExerciseSeeder.seedIfNeeded(context: context)
        #expect(BackupService.export(context: context).exercises.isEmpty)

        let bench = try #require(store.exercises(matching: "Barbell Bench Press - Medium Grip").first)
        store.updateExerciseSettings(id: bench.id, restSeconds: 90, barType: "olympic", incrementKg: 5)
        let document = BackupService.export(context: context)
        #expect(document.exercises.count == 1)
        #expect(document.exercises.first?.seedID == "Barbell_Bench_Press_-_Medium_Grip")

        let (destination, destinationContext) = try makeStore()
        ExerciseSeeder.seedIfNeeded(context: destinationContext)
        BackupService.import(document: document, context: destinationContext)
        let restored = try #require(
            destination.exercises(matching: "Barbell Bench Press - Medium Grip").first
        )
        #expect(restored.restSeconds == 90)
        #expect(restored.incrementKg == 5)
    }
}
