import Foundation
import GymCore
import SwiftData
import os

/// How far an import has got — rows written so far out of the rows to write — for the Settings
/// rows' "120 of 3,000" text. Rows are workouts (CSV) or backup items (restore).
struct ImportProgress: Sendable, Equatable {
    var done: Int
    var total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }
}

/// Writes a parsed CSV import or a decoded backup into the store on its own `ModelContext`, off
/// the main actor, saving in batches and reporting progress as it goes.
///
/// A multi-thousand-row Strong export used to insert and save every row on the main actor and
/// freeze Settings for seconds. Here the row work runs on the actor's executor; the main-actor
/// `WorkoutStore` is told afterwards through `absorbExternalImport(...)`, exactly as it learns
/// about rows a CloudKit merge wrote (`dedupeSeededRows`): re-stamped totals, a PR rebuild, the
/// cached catalogue dropped and `changeToken` bumped.
///
/// Cancellation is honoured between batches: every batch is one atomic save at a workout
/// boundary, so a cancelled import leaves whole workouts committed and the unsaved remainder
/// rolled back. Re-running the same file then skips what is already there (start minute for a
/// CSV, ids for a backup), so a cancel is resumable rather than something to clean up.
@ModelActor
actor ImportActor {
    /// Set rows (CSV) or workouts (backup) between saves. Small enough that a cancel lands
    /// within a fraction of a second; large enough that the save overhead stays negligible.
    static let batchSize = 200

    typealias ProgressHandler = @Sendable (ImportProgress) -> Void

    private static let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

    // MARK: - CSV

    /// The batched form of `WorkoutImportService.apply`: same writer, same dedupe, same report.
    /// Throws `CancellationError` when cancelled mid-way; whatever was saved before stays.
    func importWorkouts(
        _ preview: ImportPreview, progress: @escaping ProgressHandler
    ) async throws -> WorkoutImportReport {
        let interval = Self.signposter.beginInterval("importActor.workouts")
        defer { Self.signposter.endInterval("importActor.workouts", interval) }
        modelContext.autosaveEnabled = false
        let writer = WorkoutImportWriter(
            context: modelContext, source: preview.source, problems: preview.problems
        )
        let workouts = preview.workouts.sorted { $0.startedAt < $1.startedAt }
        var pendingRows = 0
        var committed = writer.report
        for (index, imported) in workouts.enumerated() {
            pendingRows += writer.insert(imported)
            guard pendingRows >= Self.batchSize || index == workouts.count - 1 else { continue }
            try commitBatch(report: &committed, current: writer.report)
            pendingRows = 0
            progress(ImportProgress(done: index + 1, total: workouts.count))
        }
        return committed
    }

    // MARK: - Backup

    /// The batched form of `BackupService.import(document:context:)` for the main store's tables.
    /// Photos and Apple Health rows live in their own containers and are written by the caller
    /// on the main actor afterwards (`BackupService.import(document:store:preferences:)`), as are
    /// the preferences. Seeding, which needs the main actor, has already happened by the time
    /// this runs. Throws `CancellationError` when cancelled mid-way; saved batches stay.
    func restore(
        _ document: BackupDocument, baseline: BackupService.SeedBaseline, progress: @escaping ProgressHandler
    ) async throws -> ImportReport {
        let interval = Self.signposter.beginInterval("importActor.restore")
        defer { Self.signposter.endInterval("importActor.restore", interval) }
        modelContext.autosaveEnabled = false
        let context = modelContext
        let total = document.exercises.count + document.routines.count + document.workouts.count
        var committed = ImportReport()
        var report = ImportReport()
        let index = BackupService.ExerciseIndex(context: context)

        BackupService.importExercises(
            document.exercises, index: index, baseline: baseline, context: context, report: &report
        )
        BackupService.importRoutines(document.routines, index: index, context: context, report: &report)
        try commitBatch(report: &committed, current: report)
        let headCount = document.exercises.count + document.routines.count
        progress(ImportProgress(done: headCount, total: total))

        var existingIDs = BackupService.existingWorkoutIDs(context: context)
        var pending = 0
        for (position, item) in document.workouts.enumerated() {
            BackupService.insertWorkout(
                item, existingIDs: &existingIDs, index: index, context: context, report: &report
            )
            pending += 1
            guard pending >= Self.batchSize || position == document.workouts.count - 1 else { continue }
            try commitBatch(report: &committed, current: report)
            pending = 0
            progress(ImportProgress(done: headCount + position + 1, total: total))
        }

        BackupService.importBodyMeasurements(document.bodyMeasurements, context: context, report: &report)
        BackupService.importEquipmentProfiles(document.equipmentProfiles, context: context, report: &report)
        BackupService.importPrograms(document.programs ?? [], context: context)
        BackupService.importAchievements(document.achievements ?? [], context: context)
        BackupService.importSchedule(document.schedule, context: context)
        BackupService.importExerciseNotes(
            document.exerciseNotes ?? [], index: index, context: context, report: &report
        )
        BackupService.importGymCards(document.gymCards ?? [], context: context)
        BackupService.importCoachInteractions(document.coachInteractions ?? [], context: context)
        try commitBatch(report: &committed, current: report)
        progress(ImportProgress(done: total, total: total))
        return committed
    }

    // MARK: - Batches

    /// Saves what the writer has inserted since the last save and advances `committed` to match,
    /// so a report only ever counts rows that are on disk. Checks for cancellation *after* the
    /// save: a cancel that arrives mid-batch still lands the batch (whole workouts, never half of
    /// one), and the throw then leaves nothing unsaved behind. A failed save is rolled back so
    /// the error names the batch, not a context full of half-linked rows.
    private func commitBatch<Report: Sendable>(report committed: inout Report, current: Report) throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        committed = current
        try Task.checkCancellation()
    }
}
