import Foundation
import GymCore
import SwiftData

/// Counts and problems from `BackupService.import`, shown in the Settings
/// import preview sheet before the user confirms.
struct ImportReport: Equatable {
    var exercisesImported = 0
    var routinesImported = 0
    var workoutsImported = 0
    var workoutsSkipped = 0
    var bodyMeasurementsImported = 0
    var equipmentProfilesImported = 0
    var problems: [String] = []

    /// "12 workouts, 3 routines, 2 custom exercises · 1 problem" for the preview sheet.
    var summary: String {
        let parts = [
            countPhrase(workoutsImported, singular: "workout"),
            countPhrase(routinesImported, singular: "routine"),
            countPhrase(exercisesImported, singular: "custom exercise")
        ].compactMap { $0 }
        var text = parts.isEmpty ? "Nothing new to import" : parts.joined(separator: ", ")
        if !problems.isEmpty {
            text += " · \(countPhrase(problems.count, singular: "problem") ?? "")"
        }
        return text
    }

    private func countPhrase(_ count: Int, singular: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

enum ImportMode {
    /// The only supported mode: never overwrites existing rows.
    case merge
}

/// Exports the live store to a `BackupDocument` and imports one back in,
/// merging — matched rows are never overwritten, and importing the same
/// file twice produces no duplicates (plan.md §6.3, §6.8).
@MainActor
enum BackupService {
    /// Below this, a seeded exercise is exported without an override row.
    static let defaultRestSeconds = 150
    static let defaultIncrementKg = 2.5

    // MARK: - Export

    static func export(context: ModelContext) -> BackupDocument {
        BackupDocument(
            exportedAt: Date(), appVersion: currentAppVersion(),
            exercises: exportExercises(context: context),
            routines: exportRoutines(context: context),
            workouts: exportWorkouts(context: context),
            bodyMeasurements: exportBodyMeasurements(context: context),
            equipmentProfiles: exportEquipmentProfiles(context: context),
            preferences: exportPreferences()
        )
    }

    private static func exportExercises(context: ModelContext) -> [BackupExercise] {
        let models = (try? context.fetch(FetchDescriptor<ExerciseModel>())) ?? []
        return models.compactMap { model -> BackupExercise? in
            let isOverride = model.isFavorite
                || model.restSeconds != defaultRestSeconds || model.incrementKg != defaultIncrementKg
            guard model.isCustom || isOverride else { return nil }
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

    private static func exportRoutines(context: ModelContext) -> [BackupRoutine] {
        let models = (try? context.fetch(FetchDescriptor<RoutineModel>())) ?? []
        return models.map { model in
            let routineExercises = (model.exercises ?? []).sorted { $0.order < $1.order }
            let exercises = routineExercises.compactMap(backupRoutineExercise)
            return BackupRoutine(
                id: model.id, name: model.name, notes: model.notes,
                progressionRule: model.progressionRule, repRangeLow: model.repRangeLow,
                repRangeHigh: model.repRangeHigh, sortOrder: model.sortOrder, exercises: exercises
            )
        }
    }

    private static func backupRoutineExercise(_ model: RoutineExerciseModel) -> BackupRoutineExercise? {
        guard let exercise = model.exercise else { return nil }
        let sets = (model.plannedSets ?? []).sorted { $0.order < $1.order }.map(backupPlannedSet)
        return BackupRoutineExercise(
            order: model.order, exerciseSeedID: exercise.seedID, exerciseName: exercise.name,
            supersetGroup: model.supersetGroup, restOverrideSeconds: model.restOverrideSeconds,
            note: model.note, plannedSets: sets
        )
    }

    private static func backupPlannedSet(_ model: PlannedSetModel) -> BackupPlannedSet {
        BackupPlannedSet(
            order: model.order, kind: model.kind, targetReps: model.targetReps,
            targetRepsHigh: model.targetRepsHigh, targetWeightKg: model.targetWeightKg,
            targetRPE: model.targetRPE, targetSeconds: model.targetSeconds
        )
    }

    private static func exportWorkouts(context: ModelContext) -> [BackupWorkout] {
        let models = (try? context.fetch(FetchDescriptor<WorkoutModel>())) ?? []
        return models.map { model in
            let workoutExercises = (model.exercises ?? []).sorted { $0.order < $1.order }
            let exercises = workoutExercises.compactMap(backupWorkoutExercise)
            return BackupWorkout(
                id: model.id, title: model.title, startedAt: model.startedAt, endedAt: model.endedAt,
                notes: model.notes, isBackfilled: model.isBackfilled, routineName: model.routineName,
                bodyweightKg: model.bodyweightKg, sourceDevice: model.sourceDevice, exercises: exercises
            )
        }
    }

    private static func backupWorkoutExercise(_ model: WorkoutExerciseModel) -> BackupWorkoutExercise? {
        guard let exercise = model.exercise else { return nil }
        let sets = (model.sets ?? []).sorted { $0.order < $1.order }.map(backupSetLog)
        return BackupWorkoutExercise(
            id: model.id, order: model.order, supersetGroup: model.supersetGroup, note: model.note,
            wasSubstitution: model.wasSubstitution, exerciseSeedID: exercise.seedID,
            exerciseName: exercise.name, sets: sets
        )
    }

    private static func backupSetLog(_ model: SetLogModel) -> BackupSetLog {
        BackupSetLog(
            id: model.id, order: model.order, kind: model.kind, weightKg: model.weightKg,
            reps: model.reps, durationSeconds: model.durationSeconds,
            distanceMeters: model.distanceMeters, assistanceKg: model.assistanceKg, rpe: model.rpe,
            isCompleted: model.isCompleted, completedAt: model.completedAt,
            prescriptionReason: model.prescriptionReason
        )
    }

    private static func exportBodyMeasurements(context: ModelContext) -> [BackupBodyMeasurement] {
        let models = (try? context.fetch(FetchDescriptor<BodyMeasurementModel>())) ?? []
        return models.map {
            BackupBodyMeasurement(id: $0.id, date: $0.date, bodyweightKg: $0.bodyweightKg, source: $0.source)
        }
    }

    private static func exportEquipmentProfiles(context: ModelContext) -> [BackupEquipmentProfile] {
        let models = (try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []
        return models.map {
            BackupEquipmentProfile(
                id: $0.id, name: $0.name, isActive: $0.isActive, barKg: $0.barKg,
                availableEquipment: $0.availableEquipment, plateStockKg: $0.plateStockKg,
                plateCounts: $0.plateCounts, collarsKg: $0.collarsKg, createdAt: $0.createdAt
            )
        }
    }

    private static func exportPreferences() -> BackupPreferences {
        let preferences = Preferences()
        return BackupPreferences(
            weightUnit: preferences.weightUnit.rawValue, effortScale: preferences.effortScale.rawValue,
            defaultRestSeconds: preferences.defaultRestSeconds, weeklyGoal: preferences.weeklyGoal,
            keepScreenAwake: preferences.keepScreenAwake, restSound: preferences.restSound,
            restHaptics: preferences.restHaptics, restScreenFlash: preferences.restScreenFlash,
            weekStartsMonday: preferences.weekStartsMonday
        )
    }

    static func currentAppVersion() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

}
