import Foundation
import GymCore
import SwiftData

extension BackupService {
    // MARK: - Import

    /// Merges a decoded document into `context`. Never overwrites: matched
    /// by id, then (for exercises/routines) by name. Existing workouts with
    /// the same id are always skipped, so re-importing the same file twice
    /// never duplicates anything.
    @discardableResult
    static func `import`(
        document: BackupDocument, context: ModelContext, mode: ImportMode = .merge
    ) -> ImportReport {
        var report = ImportReport()
        let exerciseIndex = ExerciseIndex(context: context)
        importExercises(document.exercises, index: exerciseIndex, context: context, report: &report)
        importRoutines(document.routines, index: exerciseIndex, context: context, report: &report)
        importWorkouts(document.workouts, index: exerciseIndex, context: context, report: &report)
        importBodyMeasurements(document.bodyMeasurements, context: context, report: &report)
        importEquipmentProfiles(document.equipmentProfiles, context: context, report: &report)
        try? context.save()
        return report
    }

    /// Looks up `ExerciseModel`s by seedID/id/name, kept in memory for the
    /// duration of one import so routines and workouts can resolve exercises
    /// (including ones this same import just inserted).
    final class ExerciseIndex {
        private var bySeedID: [String: ExerciseModel] = [:]
        private var byID: [UUID: ExerciseModel] = [:]
        private var byName: [String: ExerciseModel] = [:]

        init(context: ModelContext) {
            let models = (try? context.fetch(FetchDescriptor<ExerciseModel>())) ?? []
            for model in models { register(model) }
        }

        func register(_ model: ExerciseModel) {
            byID[model.id] = model
            byName[model.name.lowercased()] = model
            if let seedID = model.seedID { bySeedID[seedID] = model }
        }

        func find(seedID: String?, id: UUID?, name: String) -> ExerciseModel? {
            if let seedID, let model = bySeedID[seedID] { return model }
            if let id, let model = byID[id] { return model }
            return byName[name.lowercased()]
        }
    }

    private static func importExercises(
        _ items: [BackupExercise], index: ExerciseIndex, context: ModelContext, report: inout ImportReport
    ) {
        for item in items {
            if let existing = index.find(seedID: item.seedID, id: item.id, name: item.name) {
                applyOverride(item, to: existing)
                continue
            }
            guard item.seedID == nil else {
                report.problems.append("Skipped \"\(item.name)\": no matching built-in exercise.")
                continue
            }
            let model = ExerciseModel(
                id: item.id, name: item.name, primaryMuscles: item.primaryMuscles,
                secondaryMuscles: item.secondaryMuscles, equipment: item.equipment,
                mechanic: item.mechanic, loggingStyle: item.loggingStyle, isPerSide: item.isPerSide,
                isCustom: true, isFavorite: item.isFavorite, barType: item.barType,
                incrementKg: item.incrementKg, restSeconds: item.restSeconds,
                instructions: item.instructions, notes: item.notes, createdAt: item.createdAt
            )
            context.insert(model)
            index.register(model)
            report.exercisesImported += 1
        }
    }

    /// Applies favourite/rest/increment/bar overrides onto an already-known
    /// exercise (seeded or custom) without touching anything else.
    private static func applyOverride(_ item: BackupExercise, to model: ExerciseModel) {
        if item.isFavorite { model.isFavorite = true }
        if item.restSeconds != defaultRestSeconds { model.restSeconds = item.restSeconds }
        if item.incrementKg != defaultIncrementKg { model.incrementKg = item.incrementKg }
        if let barType = item.barType { model.barType = barType }
    }

    private static func importRoutines(
        _ items: [BackupRoutine], index: ExerciseIndex, context: ModelContext, report: inout ImportReport
    ) {
        let existingByID = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<RoutineModel>())) ?? [])
                .map { ($0.id, $0) }
        )
        for item in items where existingByID[item.id] == nil {
            let routine = RoutineModel(
                id: item.id, name: item.name, notes: item.notes, progressionRule: item.progressionRule,
                repRangeLow: item.repRangeLow, repRangeHigh: item.repRangeHigh, sortOrder: item.sortOrder
            )
            context.insert(routine)
            routine.exercises = item.exercises.compactMap { draft in
                makeRoutineExercise(draft, index: index, routine: routine, context: context, report: &report)
            }
            report.routinesImported += 1
        }
    }

    private static func makeRoutineExercise(
        _ draft: BackupRoutineExercise, index: ExerciseIndex, routine: RoutineModel,
        context: ModelContext, report: inout ImportReport
    ) -> RoutineExerciseModel? {
        let match = index.find(seedID: draft.exerciseSeedID, id: nil, name: draft.exerciseName)
        guard let exercise = match else {
            report.problems.append(
                "Skipped \"\(draft.exerciseName)\" in routine \"\(routine.name)\": exercise not found."
            )
            return nil
        }
        let model = RoutineExerciseModel(
            order: draft.order, supersetGroup: draft.supersetGroup,
            restOverrideSeconds: draft.restOverrideSeconds, note: draft.note, exercise: exercise,
            routine: routine
        )
        context.insert(model)
        model.plannedSets = draft.plannedSets.map { set in
            let plannedSet = PlannedSetModel(
                order: set.order, kind: set.kind, targetReps: set.targetReps,
                targetRepsHigh: set.targetRepsHigh, targetWeightKg: set.targetWeightKg,
                targetRPE: set.targetRPE, targetSeconds: set.targetSeconds, routineExercise: model
            )
            context.insert(plannedSet)
            return plannedSet
        }
        return model
    }

    private static func importWorkouts(
        _ items: [BackupWorkout], index: ExerciseIndex, context: ModelContext, report: inout ImportReport
    ) {
        let existingIDs = Set(
            ((try? context.fetch(FetchDescriptor<WorkoutModel>())) ?? []).map(\.id)
        )
        for item in items {
            guard !existingIDs.contains(item.id) else {
                report.workoutsSkipped += 1
                continue
            }
            let workout = WorkoutModel(
                id: item.id, title: item.title, startedAt: item.startedAt, endedAt: item.endedAt,
                notes: item.notes, isBackfilled: item.isBackfilled, routineName: item.routineName,
                bodyweightKg: item.bodyweightKg, sourceDevice: item.sourceDevice
            )
            context.insert(workout)
            workout.exercises = item.exercises.compactMap { draft in
                makeWorkoutExercise(draft, index: index, workout: workout, context: context, report: &report)
            }
            report.workoutsImported += 1
        }
    }

    private static func makeWorkoutExercise(
        _ draft: BackupWorkoutExercise, index: ExerciseIndex, workout: WorkoutModel,
        context: ModelContext, report: inout ImportReport
    ) -> WorkoutExerciseModel? {
        let match = index.find(seedID: draft.exerciseSeedID, id: nil, name: draft.exerciseName)
        guard let exercise = match else {
            report.problems.append(
                "Skipped \"\(draft.exerciseName)\" in workout \"\(workout.title)\": exercise not found."
            )
            return nil
        }
        let model = WorkoutExerciseModel(
            id: draft.id, order: draft.order, supersetGroup: draft.supersetGroup, note: draft.note,
            wasSubstitution: draft.wasSubstitution, exercise: exercise, workout: workout
        )
        context.insert(model)
        model.sets = draft.sets.map { set in
            let setModel = SetLogModel(
                id: set.id, order: set.order, kind: set.kind, weightKg: set.weightKg, reps: set.reps,
                durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters,
                assistanceKg: set.assistanceKg, rpe: set.rpe, isCompleted: set.isCompleted,
                completedAt: set.completedAt, prescriptionReason: set.prescriptionReason,
                workoutExercise: model
            )
            context.insert(setModel)
            return setModel
        }
        return model
    }

    private static func importBodyMeasurements(
        _ items: [BackupBodyMeasurement], context: ModelContext, report: inout ImportReport
    ) {
        let existingIDs = Set(
            ((try? context.fetch(FetchDescriptor<BodyMeasurementModel>())) ?? []).map(\.id)
        )
        for item in items where !existingIDs.contains(item.id) {
            let model = BodyMeasurementModel(
                id: item.id, date: item.date, bodyweightKg: item.bodyweightKg, source: item.source
            )
            context.insert(model)
            report.bodyMeasurementsImported += 1
        }
    }

    private static func importEquipmentProfiles(
        _ items: [BackupEquipmentProfile], context: ModelContext, report: inout ImportReport
    ) {
        let existingIDs = Set(
            ((try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []).map(\.id)
        )
        for item in items where !existingIDs.contains(item.id) {
            // Never let an import silently switch the user's active profile.
            let model = EquipmentProfileModel(
                id: item.id, name: item.name, isActive: false, barKg: item.barKg,
                availableEquipment: item.availableEquipment, plateStockKg: item.plateStockKg,
                plateCounts: item.plateCounts, collarsKg: item.collarsKg, createdAt: item.createdAt
            )
            context.insert(model)
            report.equipmentProfilesImported += 1
        }
    }
}
