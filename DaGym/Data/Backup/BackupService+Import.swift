import Foundation
import GymCore
import SwiftData

extension BackupService {
    // MARK: - Import

    /// Merges a decoded document into `context`. Never overwrites: matched
    /// by id, then (for exercises/routines) by name. Existing workouts with
    /// the same id are always skipped, so re-importing the same file twice
    /// never duplicates anything. The PR cache is rebuilt from history at the
    /// end, so Records and Milestones reflect the imported workouts.
    @discardableResult
    static func `import`(
        document: BackupDocument, context: ModelContext, mode: ImportMode = .merge,
        baseline: SeedBaseline = SeedBaseline()
    ) -> ImportReport {
        var report = ImportReport()
        let exerciseIndex = ExerciseIndex(context: context)
        importExercises(
            document.exercises, index: exerciseIndex, baseline: baseline, context: context, report: &report
        )
        importRoutines(document.routines, index: exerciseIndex, context: context, report: &report)
        let importedWorkouts = importWorkouts(
            document.workouts, index: exerciseIndex, context: context, report: &report
        )
        importBodyMeasurements(document.bodyMeasurements, context: context, report: &report)
        importEquipmentProfiles(document.equipmentProfiles, context: context, report: &report)
        importPrograms(document.programs ?? [], context: context)
        importAchievements(document.achievements ?? [], context: context)
        importSchedule(document.schedule, context: context)
        do {
            try context.save()
        } catch {
            report.problems.append("Saving the import failed: \(error.localizedDescription)")
            return report
        }
        if importedWorkouts > 0 {
            WorkoutStore(context: context, photoContext: nil).rebuildPersonalRecords()
        }
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
        _ items: [BackupExercise], index: ExerciseIndex, baseline: SeedBaseline, context: ModelContext,
        report: inout ImportReport
    ) {
        for item in items {
            if let existing = index.find(seedID: item.seedID, id: item.id, name: item.name) {
                applyOverride(item, to: existing, baseline: baseline)
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

    /// Applies favourite/rest/increment/bar/notes overrides onto an already-known exercise
    /// (seeded or custom) — only where the backup differs from the seeded value, so a row the
    /// user never touched on the exporting device can't undo an edit made on this one.
    private static func applyOverride(
        _ item: BackupExercise, to model: ExerciseModel, baseline: SeedBaseline
    ) {
        let seeded = baseline.values(for: item.seedID)
        if item.isFavorite { model.isFavorite = true }
        if item.restSeconds != seeded.restSeconds { model.restSeconds = item.restSeconds }
        if item.incrementKg != seeded.incrementKg { model.incrementKg = item.incrementKg }
        if item.barType != seeded.barType { model.barType = item.barType }
        if model.notes.isEmpty { model.notes = item.notes }
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
                repRangeLow: item.repRangeLow, repRangeHigh: item.repRangeHigh,
                progressionRuleJSON: item.progressionRuleJSON ?? "", createdAt: item.createdAt ?? Date(),
                updatedAt: item.updatedAt ?? Date(), sortOrder: item.sortOrder,
                isArchived: item.isArchived ?? false,
                importedFromID: item.importedFromID
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
            restOverrideSeconds: draft.restOverrideSeconds, note: draft.note,
            progressionRuleJSON: draft.progressionRuleJSON, stallJSON: draft.stallJSON ?? "{}",
            trainingMaxKg: draft.trainingMaxKg, excludeFromProgression: draft.excludeFromProgression ?? false,
            exercise: exercise, routine: routine
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

    /// Returns how many workouts were inserted, so the caller knows whether a PR rebuild is due.
    private static func importWorkouts(
        _ items: [BackupWorkout], index: ExerciseIndex, context: ModelContext, report: inout ImportReport
    ) -> Int {
        let existingIDs = Set(
            ((try? context.fetch(FetchDescriptor<WorkoutModel>())) ?? []).map(\.id)
        )
        var inserted = 0
        for item in items {
            guard !existingIDs.contains(item.id) else {
                report.workoutsSkipped += 1
                continue
            }
            let workout = WorkoutModel(
                id: item.id, title: item.title, startedAt: item.startedAt, endedAt: item.endedAt,
                notes: item.notes, isBackfilled: item.isBackfilled, routineID: item.routineID,
                routineName: item.routineName, bodyweightKg: item.bodyweightKg,
                sourceDevice: item.sourceDevice, healthKitID: item.healthKitID
            )
            context.insert(workout)
            workout.exercises = item.exercises.compactMap { draft in
                makeWorkoutExercise(draft, index: index, workout: workout, context: context, report: &report)
            }
            report.workoutsImported += 1
            inserted += 1
        }
        return inserted
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
            wasSubstitution: draft.wasSubstitution, wasPlannedDeload: draft.wasPlannedDeload ?? false,
            exercise: exercise, workout: workout
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

    private static func importPrograms(_ items: [BackupProgram], context: ModelContext) {
        let existingIDs = Set(((try? context.fetch(FetchDescriptor<ProgramModel>())) ?? []).map(\.id))
        let existing = (try? context.fetch(FetchDescriptor<ProgramModel>())) ?? []
        let hasActive = existing.contains(where: \.isActive)
        for item in items where !existingIDs.contains(item.id) {
            // A restore onto an empty store brings the active program back; a merge into a store
            // that already has one never steals its place.
            let model = ProgramModel(
                id: item.id, name: item.name, weeks: item.weeks, startedAt: item.startedAt,
                completedAt: item.completedAt, isActive: item.isActive && !hasActive,
                createdAt: item.createdAt
            )
            model.routineIDs = item.routineIDs
            context.insert(model)
            model.programWeeks = item.programWeeks.map { week in
                let weekModel = ProgramWeekModel(
                    id: week.id, index: week.index, kind: week.kind, program: model
                )
                context.insert(weekModel)
                return weekModel
            }
        }
    }

    private static func importAchievements(_ items: [BackupAchievement], context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AchievementModel>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        let existingKeys = Set(existing.map { "\($0.milestoneID)|\($0.tier)" })
        for item in items
        where !existingIDs.contains(item.id) && !existingKeys.contains("\(item.milestoneID)|\(item.tier)") {
            context.insert(
                AchievementModel(
                    id: item.id, milestoneID: item.milestoneID, tier: item.tier, earnedAt: item.earnedAt,
                    workoutID: item.workoutID
                )
            )
        }
    }

    /// Only fills an empty schedule — an existing one is the user's current plan on this device.
    private static func importSchedule(_ item: BackupSchedule?, context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<ScheduleModel>())) ?? 0
        guard let item, existing == 0 else { return }
        context.insert(ScheduleModel(scheduleJSON: item.scheduleJSON, updatedAt: item.updatedAt))
    }
}
