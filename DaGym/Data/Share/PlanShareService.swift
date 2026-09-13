import Foundation
import GymCore
import SwiftData

/// Builds `.gymplan` files from the store (a single routine, or a whole program with all of its
/// routines) and merges a decoded file back in (plan.md §6.8). Only plans travel — never
/// workouts, weigh-ins or photos. See `PlanShareService+Import.swift` for the merge side.
@MainActor
enum PlanShareService {
    // MARK: - Export

    /// A single routine as a `.gymplan` file, with any custom exercises it uses.
    static func exportRoutine(id: UUID, context: ModelContext) -> PlanDocument? {
        guard let model = fetchRoutine(id: id, context: context) else { return nil }
        var customExercises: [UUID: PlanExercise] = [:]
        let routine = planRoutine(model, customExercises: &customExercises)
        return PlanDocument(
            exportedAt: Date(), appVersion: BackupService.currentAppVersion(),
            exercises: Array(customExercises.values), routines: [routine]
        )
    }

    /// A program plus every routine in its day cycle, deduplicated, with their custom exercises.
    static func exportProgram(id: UUID, context: ModelContext) -> PlanDocument? {
        guard let program = fetchProgram(id: id, context: context) else { return nil }
        var customExercises: [UUID: PlanExercise] = [:]
        var planRoutines: [UUID: PlanRoutine] = [:]
        for routineID in Set(program.routineIDs) {
            guard let routineModel = fetchRoutine(id: routineID, context: context) else { continue }
            planRoutines[routineID] = planRoutine(routineModel, customExercises: &customExercises)
        }
        let orderedRoutines = program.routineIDs.compactMap { planRoutines[$0] }
        // `routines` here is deduplicated by id (a day cycle can repeat a routine); `routineIDs`
        // below keeps the full cycle order so import can rebuild the day mapping.
        let uniqueRoutines = Array(planRoutines.values)
        let weeks = (program.programWeeks ?? []).sorted { $0.index < $1.index }.map {
            PlanProgramWeek(index: $0.index, kind: $0.kind)
        }
        let planProgram = PlanProgram(
            id: program.id, name: program.name, weeks: program.weeks,
            routineIDs: orderedRoutines.map(\.id), programWeeks: weeks
        )
        return PlanDocument(
            exportedAt: Date(), appVersion: BackupService.currentAppVersion(),
            exercises: Array(customExercises.values), routines: uniqueRoutines, program: planProgram
        )
    }

    private static func planRoutine(
        _ model: RoutineModel, customExercises: inout [UUID: PlanExercise]
    ) -> PlanRoutine {
        let routineExercises = (model.exercises ?? []).sorted { $0.order < $1.order }
        let exercises = routineExercises.compactMap { slot -> PlanRoutineExercise? in
            guard let exercise = slot.exercise else { return nil }
            if exercise.isCustom { customExercises[exercise.id] = planExercise(exercise) }
            let sets = (slot.plannedSets ?? []).sorted { $0.order < $1.order }.map(planSet)
            return PlanRoutineExercise(
                order: slot.order, exerciseSeedID: exercise.seedID, exerciseName: exercise.name,
                supersetGroup: slot.supersetGroup, restOverrideSeconds: slot.restOverrideSeconds,
                note: slot.note, ruleJSON: slot.progressionRuleJSON, sets: sets
            )
        }
        return PlanRoutine(
            id: model.id, name: model.name, notes: model.notes, progressionRule: model.progressionRule,
            repRangeLow: model.repRangeLow, repRangeHigh: model.repRangeHigh,
            ruleJSON: model.progressionRuleJSON.isEmpty ? nil : model.progressionRuleJSON,
            sortOrder: model.sortOrder, exercises: exercises
        )
    }

    private static func planExercise(_ model: ExerciseModel) -> PlanExercise {
        PlanExercise(
            id: model.id, name: model.name, primaryMuscles: model.primaryMuscles,
            secondaryMuscles: model.secondaryMuscles, equipment: model.equipment,
            mechanic: model.mechanic, loggingStyle: model.loggingStyle, isPerSide: model.isPerSide,
            barType: model.barType, incrementKg: model.incrementKg, restSeconds: model.restSeconds,
            instructions: model.instructions, notes: model.notes
        )
    }

    private static func planSet(_ model: PlannedSetModel) -> PlanSet {
        PlanSet(
            order: model.order, kind: model.kind, targetReps: model.targetReps,
            targetRepsHigh: model.targetRepsHigh, targetWeightKg: model.targetWeightKg,
            targetRPE: model.targetRPE, targetSeconds: model.targetSeconds
        )
    }

    // MARK: - Fetch helpers

    private static func fetchRoutine(id: UUID, context: ModelContext) -> RoutineModel? {
        var descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchProgram(id: UUID, context: ModelContext) -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
