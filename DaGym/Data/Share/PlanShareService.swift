import CryptoKit
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
            id: sharedID(for: program.id), name: program.name, weeks: program.weeks,
            routineIDs: orderedRoutines.map(\.id), programWeeks: weeks
        )
        return PlanDocument(
            exportedAt: Date(), appVersion: BackupService.currentAppVersion(),
            exercises: Array(customExercises.values), routines: uniqueRoutines, program: planProgram
        )
    }

    // MARK: - What a shared plan deliberately leaves behind
    //
    // A `.gymplan` goes to another person over Messages or AirDrop. What travels is the *plan*:
    // which exercises, how many sets, what rep range, what rest. What does not travel:
    //
    // * the sender's own notes — `ExerciseModel.notes` and the per-slot `note` are a training
    //   diary ("left shoulder still sore", "grip fails first"), not part of the plan;
    // * the sender's working weights — `targetWeightKg` is what *they* lift, and it is both
    //   personal and useless (often unsafe) to the recipient, who should start from their own
    //   numbers. Rep, RPE and time targets are the prescription, so those do travel;
    // * the sender's database identifiers — `RoutineModel.id`, `ProgramModel.id` and
    //   `ExerciseModel.id` are stable, device-linked UUIDs that correlate one shared file with
    //   another. `sharedID` replaces each with a salted hash: stable across re-exports of the
    //   same routine (so the recipient's "already imported" check still works) and carrying
    //   nothing back to the sender's store.

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
                note: "", ruleJSON: slot.progressionRuleJSON, sets: sets
            )
        }
        return PlanRoutine(
            id: sharedID(for: model.id), name: model.name, notes: model.notes,
            progressionRule: model.progressionRule,
            repRangeLow: model.repRangeLow, repRangeHigh: model.repRangeHigh,
            ruleJSON: model.progressionRuleJSON.isEmpty ? nil : model.progressionRuleJSON,
            sortOrder: model.sortOrder, exercises: exercises
        )
    }

    private static func planExercise(_ model: ExerciseModel) -> PlanExercise {
        PlanExercise(
            id: sharedID(for: model.id), name: model.name, primaryMuscles: model.primaryMuscles,
            secondaryMuscles: model.secondaryMuscles, equipment: model.equipment,
            mechanic: model.mechanic, loggingStyle: model.loggingStyle, isPerSide: model.isPerSide,
            barType: model.barType, incrementKg: model.incrementKg, restSeconds: model.restSeconds,
            instructions: model.instructions, notes: ""
        )
    }

    private static func planSet(_ model: PlannedSetModel) -> PlanSet {
        PlanSet(
            order: model.order, kind: model.kind, targetReps: model.targetReps,
            targetRepsHigh: model.targetRepsHigh, targetWeightKg: nil,
            targetRPE: model.targetRPE, targetSeconds: model.targetSeconds
        )
    }

    /// A stable, one-way alias for a local identifier: `SHA256(salt + uuid)`, first 16 bytes.
    /// Deterministic, so two exports of the same routine share an id and the recipient's
    /// `importedFromID` dedupe still works; irreversible, so the file carries nothing that points
    /// back at the sender's own rows.
    static func sharedID(for id: UUID) -> UUID {
        let digest = SHA256.hash(data: Data("dagym.plan.share.v1:\(id.uuidString)".utf8))
        var bytes = (uuid_t)(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &bytes) { buffer in
            for (offset, byte) in digest.prefix(16).enumerated() { buffer[offset] = byte }
        }
        return UUID(uuid: bytes)
    }

    // MARK: - Fetch helpers

    /// `mergedIntoID == nil`: a routine that lost a seed fold is a tombstone that still owns its
    /// slots, so sharing one would send the recipient a complete duplicate of a routine they are
    /// about to receive anyway (see `BackupService.liveRoutines`).
    private static func fetchRoutine(id: UUID, context: ModelContext) -> RoutineModel? {
        var descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first.flatMap { $0.mergedIntoID == nil ? $0 : nil }
    }

    private static func fetchProgram(id: UUID, context: ModelContext) -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
