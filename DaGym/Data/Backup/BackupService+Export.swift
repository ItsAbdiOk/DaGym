import Foundation
import GymCore
import SwiftData

extension BackupService {
    /// Everything one export pulls out of the store, plus anything it couldn't carry faithfully.
    /// Export used to be silent: a workout exercise whose exercise row had been deleted was
    /// dropped on the floor, so all history on a deleted custom exercise vanished from the backup
    /// with nothing to show for it. Now it survives, and the user is told.
    struct ExportResult {
        var document: BackupDocument
        var problems: [String] = []
    }

    /// The name a workout exercise is exported under when its exercise row is gone. The importer
    /// recreates a single custom exercise with this name, so the sets survive with their weights,
    /// reps and dates intact even though the original exercise's identity is already lost.
    static let deletedExerciseName = "Deleted Exercise"

    /// Base64 in JSON is ~1.37× the bytes, and `JSONEncoder` builds the whole file in memory
    /// before anything can write it — so the peak is several times the image bytes. Photos are
    /// exported newest-first until this much image data is in; anything past it exports as
    /// metadata only, with a problem naming how many were left. 64 MB is roughly 130 photos at the
    /// size `PhotoProcessor` stores them, and keeps the export well inside what an older phone can
    /// encode without being killed.
    static let photoByteBudget = 64 * 1024 * 1024

    /// The full export. `photoContext`/`healthContext` are the two local-only stores
    /// (`WorkoutStore.photoContext`, `.healthContext`); passing nil simply leaves those sections
    /// out, which is what a caller that only has the main context wants.
    static func exportResult(
        context: ModelContext, baseline: SeedBaseline = SeedBaseline(),
        photoContext: ModelContext? = nil, healthContext: ModelContext? = nil,
        preferences: Preferences? = nil
    ) -> ExportResult {
        var problems: [String] = []
        let photos = photoContext.map { exportPhotos(context: $0, problems: &problems) } ?? []
        let document = BackupDocument(
            exportedAt: Date(), appVersion: currentAppVersion(),
            exercises: exportExercises(context: context, baseline: baseline),
            routines: exportRoutines(context: context),
            workouts: exportWorkouts(context: context, problems: &problems),
            bodyMeasurements: exportBodyMeasurements(context: context),
            equipmentProfiles: exportEquipmentProfiles(context: context),
            preferences: exportPreferences(preferences ?? Preferences()),
            programs: exportPrograms(context: context),
            achievements: exportAchievements(context: context),
            schedule: exportSchedule(context: context),
            exerciseNotes: exportExerciseNotes(context: context),
            progressPhotos: photos,
            gymCards: exportGymCards(context: context),
            coachInteractions: exportCoachInteractions(context: context),
            healthImports: healthContext.map(exportHealthImports(context:))
        )
        return ExportResult(document: document, problems: problems)
    }

    // MARK: - Exercises, routines

    /// Exercises that are still real rows. A row that lost a seed fold is a **tombstone**
    /// (`ExerciseModel.mergedIntoID`), kept alive only so CloudKit can still deliver children to
    /// it — every read path hides it. Exporting one wrote the duplicate into the file, and the
    /// importer has no idea it was a tombstone, so it arrived on the other device as a second
    /// real "Bench Press" sitting in the library next to the first.
    nonisolated static func liveExercises(context: ModelContext) -> [ExerciseModel] {
        // Filtered in memory, not in the #Predicate: SwiftData does not translate an optional
        // UUID compared against nil, and the fetch comes back empty — which silently made every
        // exercise lookup in import and plan sharing fail to match anything.
        let all = (try? context.fetch(FetchDescriptor<ExerciseModel>())) ?? []
        return all.filter { $0.mergedIntoID == nil }
    }

    /// The same, for routines (`RoutineModel.mergedIntoID`, stamped by `dedupeRoutines()`). A
    /// routine tombstone still *owns its slots*, so exporting one shipped a complete duplicate
    /// routine, not just an empty shell. Archived routines are deliberately still exported — a
    /// backup carries them, a tombstone is not the user's data.
    nonisolated static func liveRoutines(context: ModelContext) -> [RoutineModel] {
        let all = (try? context.fetch(FetchDescriptor<RoutineModel>())) ?? []
        return all.filter { $0.mergedIntoID == nil }
    }

    static func exportExercises(context: ModelContext, baseline: SeedBaseline) -> [BackupExercise] {
        let models = liveExercises(context: context)
        return models.compactMap { model -> BackupExercise? in
            guard model.isCustom || baseline.isOverridden(model) else { return nil }
            return BackupExercise(
                id: model.id, seedID: model.seedID, name: model.name,
                primaryMuscles: model.primaryMuscles, secondaryMuscles: model.secondaryMuscles,
                equipment: model.equipment, mechanic: model.mechanic, loggingStyle: model.loggingStyle,
                isPerSide: model.isPerSide, isCustom: model.isCustom, isFavorite: model.isFavorite,
                barType: model.barType, incrementKg: model.incrementKg, restSeconds: model.restSeconds,
                instructions: model.isCustom ? model.instructions : "", notes: model.notes,
                createdAt: model.createdAt
            )
        }
    }

    static func exportRoutines(context: ModelContext) -> [BackupRoutine] {
        let models = liveRoutines(context: context)
        return models.map { model in
            let routineExercises = (model.exercises ?? []).sorted { $0.order < $1.order }
            return BackupRoutine(
                id: model.id, name: model.name, notes: model.notes,
                progressionRule: model.progressionRule, repRangeLow: model.repRangeLow,
                repRangeHigh: model.repRangeHigh, progressionRuleJSON: model.progressionRuleJSON,
                createdAt: model.createdAt, updatedAt: model.updatedAt, sortOrder: model.sortOrder,
                isArchived: model.isArchived, importedFromID: model.importedFromID,
                symbolName: model.symbolName, tint: model.tint,
                exercises: routineExercises.compactMap(backupRoutineExercise)
            )
        }
    }

    private static func backupRoutineExercise(_ model: RoutineExerciseModel) -> BackupRoutineExercise? {
        guard let exercise = model.exercise else { return nil }
        let sets = (model.plannedSets ?? []).sorted { $0.order < $1.order }.map(backupPlannedSet)
        return BackupRoutineExercise(
            order: model.order, exerciseSeedID: exercise.seedID, exerciseName: exercise.name,
            supersetGroup: model.supersetGroup, restOverrideSeconds: model.restOverrideSeconds,
            note: model.note, progressionRuleJSON: model.progressionRuleJSON, stallJSON: model.stallJSON,
            trainingMaxKg: model.trainingMaxKg, excludeFromProgression: model.excludeFromProgression,
            plannedSets: sets
        )
    }

    private static func backupPlannedSet(_ model: PlannedSetModel) -> BackupPlannedSet {
        BackupPlannedSet(
            order: model.order, kind: model.kind, targetReps: model.targetReps,
            targetRepsHigh: model.targetRepsHigh, targetWeightKg: model.targetWeightKg,
            targetRPE: model.targetRPE, targetSeconds: model.targetSeconds,
            targetDistanceMeters: model.targetDistanceMeters
        )
    }

    // MARK: - Workouts

    static func exportWorkouts(context: ModelContext, problems: inout [String]) -> [BackupWorkout] {
        let models = (try? context.fetch(FetchDescriptor<WorkoutModel>())) ?? []
        var orphanCount = 0
        let workouts = models.map { model -> BackupWorkout in
            let workoutExercises = (model.exercises ?? []).sorted { $0.order < $1.order }
            let exercises = workoutExercises.map { entry -> BackupWorkoutExercise in
                if entry.exercise == nil { orphanCount += 1 }
                return backupWorkoutExercise(entry)
            }
            return BackupWorkout(
                id: model.id, title: model.title, startedAt: model.startedAt, endedAt: model.endedAt,
                notes: model.notes, isBackfilled: model.isBackfilled, routineID: model.routineID,
                routineName: model.routineName, bodyweightKg: model.bodyweightKg,
                sourceDevice: model.sourceDevice, healthKitID: model.healthKitID, exercises: exercises
            )
        }
        if orphanCount > 0 {
            problems.append(
                "\(orphanCount) logged exercise\(orphanCount == 1 ? "" : "s") no longer point at an "
                    + "exercise in your library (it was deleted). The sets are in the backup under "
                    + "\"\(deletedExerciseName)\"."
            )
        }
        return workouts
    }

    /// Never returns nil: a row whose exercise was deleted still carries its sets, under
    /// `deletedExerciseName`, rather than disappearing from the backup entirely.
    private static func backupWorkoutExercise(_ model: WorkoutExerciseModel) -> BackupWorkoutExercise {
        let sets = (model.sets ?? []).sorted { $0.order < $1.order }.map(backupSetLog)
        return BackupWorkoutExercise(
            id: model.id, order: model.order, supersetGroup: model.supersetGroup, note: model.note,
            wasSubstitution: model.wasSubstitution, wasPlannedDeload: model.wasPlannedDeload,
            excludedFromProgression: model.excludedFromProgression, routineID: model.routineID,
            exerciseSeedID: model.exercise?.seedID,
            exerciseName: model.exercise?.name ?? deletedExerciseName, sets: sets
        )
    }

    private static func backupSetLog(_ model: SetLogModel) -> BackupSetLog {
        BackupSetLog(
            id: model.id, order: model.order, kind: model.kind, weightKg: model.weightKg,
            reps: model.reps, durationSeconds: model.durationSeconds,
            distanceMeters: model.distanceMeters, assistanceKg: model.assistanceKg, rpe: model.rpe,
            isCompleted: model.isCompleted, completedAt: model.completedAt,
            prescriptionReason: model.prescriptionReason, inclinePercent: model.inclinePercent
        )
    }

    // MARK: - Everything else

    static func exportBodyMeasurements(context: ModelContext) -> [BackupBodyMeasurement] {
        let models = (try? context.fetch(FetchDescriptor<BodyMeasurementModel>())) ?? []
        return models.map {
            BackupBodyMeasurement(id: $0.id, date: $0.date, bodyweightKg: $0.bodyweightKg, source: $0.source)
        }
    }

    static func exportEquipmentProfiles(context: ModelContext) -> [BackupEquipmentProfile] {
        let models = (try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []
        return models.map {
            BackupEquipmentProfile(
                id: $0.id, name: $0.name, isActive: $0.isActive, barKg: $0.barKg,
                availableEquipment: $0.availableEquipment, plateStockKg: $0.plateStockKg,
                plateCounts: $0.plateCounts, collarsKg: $0.collarsKg, createdAt: $0.createdAt,
                seedKey: $0.seedKey
            )
        }
    }

    static func exportPrograms(context: ModelContext) -> [BackupProgram] {
        let models = (try? context.fetch(FetchDescriptor<ProgramModel>())) ?? []
        return models.map { model in
            let weeks = (model.programWeeks ?? []).sorted { $0.index < $1.index }.map {
                BackupProgramWeek(id: $0.id, index: $0.index, kind: $0.kind)
            }
            return BackupProgram(
                id: model.id, name: model.name, weeks: model.weeks, startedAt: model.startedAt,
                completedAt: model.completedAt, isActive: model.isActive, routineIDs: model.routineIDs,
                createdAt: model.createdAt, programWeeks: weeks
            )
        }
    }

    static func exportAchievements(context: ModelContext) -> [BackupAchievement] {
        let models = (try? context.fetch(FetchDescriptor<AchievementModel>())) ?? []
        return models.map {
            BackupAchievement(
                id: $0.id, milestoneID: $0.milestoneID, tier: $0.tier, earnedAt: $0.earnedAt,
                workoutID: $0.workoutID
            )
        }
    }

    static func exportSchedule(context: ModelContext) -> BackupSchedule? {
        var descriptor = FetchDescriptor<ScheduleModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let model = (try? context.fetch(descriptor))?.first else { return nil }
        return BackupSchedule(scheduleJSON: model.scheduleJSON, updatedAt: model.updatedAt)
    }

    /// Notes are keyed by `exerciseID`, which a restore onto a fresh store won't reproduce for a
    /// seeded exercise — so the exercise's seedID and name travel alongside, and the importer
    /// re-points the note at whatever local row those resolve to.
    static func exportExerciseNotes(context: ModelContext) -> [BackupExerciseNote] {
        let notes = (try? context.fetch(FetchDescriptor<ExerciseNoteModel>())) ?? []
        let exercises = liveExercises(context: context)
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return notes.map { note in
            let exercise = note.exerciseID.flatMap { byID[$0] }
            return BackupExerciseNote(
                id: note.id, exerciseSeedID: exercise?.seedID, exerciseName: exercise?.name ?? "",
                text: note.text, scope: note.scope, createdAt: note.createdAt, workoutID: note.workoutID
            )
        }
    }

    static func exportGymCards(context: ModelContext) -> [BackupGymCard] {
        let models = (try? context.fetch(FetchDescriptor<GymCardModel>())) ?? []
        return models.map {
            BackupGymCard(
                id: $0.id, name: $0.name, value: $0.value, symbology: $0.symbology,
                sortOrder: $0.sortOrder, createdAt: $0.createdAt, lastUsedAt: $0.lastUsedAt
            )
        }
    }

    static func exportCoachInteractions(context: ModelContext) -> [BackupCoachInteraction] {
        let models = (try? context.fetch(FetchDescriptor<CoachInteractionModel>())) ?? []
        return models.map {
            BackupCoachInteraction(
                id: $0.id, rule: $0.rule, fingerprint: $0.fingerprint, outcome: $0.outcome, date: $0.date
            )
        }
    }

    /// Newest photos first, with their JPEG bytes, until `photoByteBudget` is spent — a phone
    /// can't base64 an unbounded photo library into one JSON file, and a backup that fails to
    /// encode is worse than one that carries the most recent photos and says so.
    static func exportPhotos(context: ModelContext, problems: inout [String]) -> [BackupProgressPhoto] {
        let descriptor = FetchDescriptor<ProgressPhotoModel>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        var budget = photoByteBudget
        var skipped = 0
        let photos = models.map { model -> BackupProgressPhoto in
            var base64: String?
            if let data = model.imageData, data.count <= budget {
                budget -= data.count
                base64 = data.base64EncodedString()
            } else if model.imageData != nil {
                skipped += 1
            }
            return BackupProgressPhoto(
                id: model.id, date: model.date, pose: model.pose, bodyweightKg: model.bodyweightKg,
                notes: model.notes, imageBase64: base64
            )
        }
        if skipped > 0 {
            problems.append(
                "\(skipped) progress photo\(skipped == 1 ? "" : "s") were too large to fit in one "
                    + "backup file; their dates and notes are included, the images aren't."
            )
        }
        return photos
    }

    static func exportHealthImports(context: ModelContext) -> BackupHealthImport {
        let imported = (try? context.fetch(FetchDescriptor<ImportedHealthWorkoutModel>())) ?? []
        let ignored = (try? context.fetch(FetchDescriptor<IgnoredHealthWorkoutModel>())) ?? []
        return BackupHealthImport(
            imported: imported.map {
                BackupImportedHealthWorkout(
                    id: $0.id, healthKitID: $0.healthKitID, title: $0.title, startedAt: $0.startedAt,
                    endedAt: $0.endedAt, importedAt: $0.importedAt
                )
            },
            ignoredHealthKitIDs: ignored.map(\.healthKitID)
        )
    }
}
