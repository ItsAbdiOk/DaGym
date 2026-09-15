#if DEBUG
import Foundation
import GymCore
import SwiftData

// @available(*, deprecated, message: "Use scripts/cloudkit-schema.sh (CloudKitSchemaInitializer) instead")
/// Debug-only rows that force every synced record type and field into the CloudKit
/// Development schema. SwiftData creates a CloudKit record type the first time a row of it
/// exports, and a field the first time a row carrying a non-nil value for it exports — so a
/// device that has never earned an achievement, set a schedule or tombstoned an exercise
/// never creates those types or fields, and "Deploy Schema Changes" has nothing to promote. A
/// field missing from Production stalls export silently and forever.
///
/// Usage: insert, save, wait for the export (about a minute), remove, save. The record types survive the
/// delete; only the rows go. Every optional is populated so no field is left behind.
///
/// DEPRECATED: superseded by `scripts/cloudkit-schema.sh`, which launches the app with
/// `-dgInitCloudKitSchema` (`CloudKitSchemaInitializer`) and deploys with `cktool` — no probe
/// rows, no waiting, no console. Kept only as a manual fallback until the script has been
/// through a real deploy; delete it (and `DeveloperSettingsSection`) after that.
@MainActor
enum CloudKitSchemaProbe {
    static let marker = "CloudKit schema probe"

    /// Whether probe rows are currently in the store.
    static func isPresent(in context: ModelContext) -> Bool {
        let name = marker
        let descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.name == name })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    static func insert(into context: ModelContext) {
        let now = Date()
        let id = UUID()
        let exercise = ExerciseModel(
            seedID: marker, name: marker, primaryMuscles: ["chest"], secondaryMuscles: ["triceps"],
            equipment: "barbell", mechanic: "compound", barType: "standard", instructions: marker,
            notes: marker, dataSource: marker, sourceURL: marker, licence: marker, authors: [marker],
            machine: Machine.legPress.rawValue
        )
        // Tombstoned so it never appears in the library — and so the merge fields export.
        exercise.mergedIntoID = id
        exercise.mergedAt = now
        context.insert(exercise)

        let routine = RoutineModel(name: marker, notes: marker, progressionRuleJSON: "{}", importedFromID: id)
        routine.mergedIntoID = id
        routine.mergedAt = now
        context.insert(routine)
        let routineExercise = RoutineExerciseModel(
            supersetGroup: 1, restOverrideSeconds: 90, note: marker, progressionRuleJSON: "{}",
            trainingMaxKg: 100, exercise: exercise, routine: routine
        )
        context.insert(routineExercise)
        context.insert(PlannedSetModel(
            targetReps: 5, targetRepsHigh: 8, targetWeightKg: 60, targetRPE: 8, targetSeconds: 30,
            targetDistanceMeters: 5000, routineExercise: routineExercise
        ))

        let workout = WorkoutModel(
            title: marker, endedAt: now, notes: marker, routineID: id, routineName: marker,
            bodyweightKg: 80, healthKitID: marker
        )
        context.insert(workout)
        let workoutExercise = WorkoutExerciseModel(
            supersetGroup: 1, note: marker, routineID: id, exercise: exercise, workout: workout
        )
        context.insert(workoutExercise)
        context.insert(SetLogModel(
            durationSeconds: 30, distanceMeters: 100, inclinePercent: 2.5, assistanceKg: 10, rpe: 8,
            completedAt: now, prescriptionReason: marker, workoutExercise: workoutExercise
        ))

        context.insert(BodyMeasurementModel(bodyweightKg: 80, source: marker))
        context.insert(PersonalRecordModel(exerciseID: id, workoutID: id))
        context.insert(PersonalRecordEventModel(exerciseID: id, workoutID: id))
        context.insert(EquipmentProfileModel(
            name: marker, availableEquipment: ["barbell"], plateStockKg: [20], plateCounts: [2],
            seedKey: marker, restrictsMachines: true, availableMachines: [Machine.legPress.rawValue]
        ))
        // The store reads the newest schedule row, so a probe row would shadow a real one:
        // only add one when the device has none (which is exactly when the type is missing).
        if ((try? context.fetchCount(FetchDescriptor<ScheduleModel>())) ?? 0) == 0 {
            context.insert(ScheduleModel())
        }
        context.insert(AchievementModel(milestoneID: marker, workoutID: id))
        let program = ProgramModel(name: marker, startedAt: now, completedAt: now)
        context.insert(program)
        context.insert(ProgramWeekModel(program: program))
        context.insert(ExerciseNoteModel(exerciseID: id, text: marker, workoutID: id))
        context.insert(GymCardModel(name: marker, value: marker, lastUsedAt: now))
        context.insert(CoachInteractionModel(rule: marker, fingerprint: marker))
    }

    static func remove(from context: ModelContext) {
        let name = marker
        delete(context, #Predicate<ExerciseModel> { $0.name == name })
        delete(context, #Predicate<RoutineModel> { $0.name == name })
        delete(context, #Predicate<WorkoutModel> { $0.title == name })
        delete(context, #Predicate<BodyMeasurementModel> { $0.source == name })
        delete(context, #Predicate<EquipmentProfileModel> { $0.name == name })
        delete(context, #Predicate<AchievementModel> { $0.milestoneID == name })
        delete(context, #Predicate<ProgramModel> { $0.name == name })
        delete(context, #Predicate<ExerciseNoteModel> { $0.text == name })
        delete(context, #Predicate<GymCardModel> { $0.name == name })
        delete(context, #Predicate<CoachInteractionModel> { $0.rule == name })
        deleteUnmarkedProbeRows(context)
    }

    private static func delete<T: PersistentModel>(_ context: ModelContext, _ predicate: Predicate<T>) {
        let rows = (try? context.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
        rows.forEach(context.delete)
    }

    /// Child rows cascade with their parents. Personal-record rows carry no marker string, but
    /// the probe gives them the same id for exercise and workout — a real row never has that.
    /// The schedule row has no marker either; an empty one is the probe's (or an empty real
    /// one, which the store recreates on demand, so nothing is lost).
    private static func deleteUnmarkedProbeRows(_ context: ModelContext) {
        for record in (try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? []
        where record.exerciseID != nil && record.exerciseID == record.workoutID {
            context.delete(record)
        }
        for event in (try? context.fetch(FetchDescriptor<PersonalRecordEventModel>())) ?? []
        where event.exerciseID != nil && event.exerciseID == event.workoutID {
            context.delete(event)
        }
        for schedule in (try? context.fetch(FetchDescriptor<ScheduleModel>())) ?? []
        where schedule.scheduleJSON == "{}" && schedule.eventIDsJSON == "{}" {
            context.delete(schedule)
        }
    }
}
#endif
