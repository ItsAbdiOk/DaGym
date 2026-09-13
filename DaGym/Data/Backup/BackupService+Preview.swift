import Foundation
import GymCore
import SwiftData

extension BackupService {
    /// Read-only prediction of what `import` would do, for the Settings
    /// import preview sheet — never mutates `context`. Mirrors `import`'s
    /// matching rules (id, then seedID/name) without inserting anything.
    static func preview(document: BackupDocument, context: ModelContext) -> ImportReport {
        var report = ImportReport()
        previewExercises(document.exercises, context: context, report: &report)
        previewCounts(document, context: context, report: &report)
        return report
    }

    private static func previewExercises(
        _ items: [BackupExercise], context: ModelContext, report: inout ImportReport
    ) {
        let index = ExerciseIndex(context: context)
        for item in items where index.find(seedID: item.seedID, id: item.id, name: item.name) == nil {
            if item.seedID == nil {
                report.exercisesImported += 1
            } else {
                report.problems.append("No matching built-in exercise for \"\(item.name)\".")
            }
        }
    }

    private static func previewCounts(
        _ document: BackupDocument, context: ModelContext, report: inout ImportReport
    ) {
        let existingRoutineIDs = Set(((try? context.fetch(FetchDescriptor<RoutineModel>())) ?? []).map(\.id))
        report.routinesImported = document.routines.filter { !existingRoutineIDs.contains($0.id) }.count

        let existingEquipmentIDs = Set(
            ((try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []).map(\.id)
        )
        report.equipmentProfilesImported = document.equipmentProfiles
            .filter { !existingEquipmentIDs.contains($0.id) }.count

        let existingMeasurementIDs = Set(
            ((try? context.fetch(FetchDescriptor<BodyMeasurementModel>())) ?? []).map(\.id)
        )
        report.bodyMeasurementsImported = document.bodyMeasurements
            .filter { !existingMeasurementIDs.contains($0.id) }.count

        let existingWorkoutIDs = Set(((try? context.fetch(FetchDescriptor<WorkoutModel>())) ?? []).map(\.id))
        for workout in document.workouts {
            if existingWorkoutIDs.contains(workout.id) {
                report.workoutsSkipped += 1
            } else {
                report.workoutsImported += 1
            }
        }
    }
}
