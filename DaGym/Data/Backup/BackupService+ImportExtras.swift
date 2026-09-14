import Foundation
import UIKit
import GymCore
import SwiftData

extension BackupService {
    /// The tables a restore used to drop entirely: per-exercise notes, progress photos, gym cards,
    /// coach dismissals and the Apple Health import bookkeeping. All keyed by id, so re-importing
    /// the same file twice adds nothing.
    ///
    /// `photoContext`/`healthContext` are the two local-only stores; nil means "this caller has no
    /// such store", and those sections are skipped rather than silently lost — `import` reports
    /// how many rows it couldn't place.
    static func importExtras(
        _ document: BackupDocument, index: ExerciseIndex, context: ModelContext,
        photoContext: ModelContext? = nil, healthContext: ModelContext? = nil,
        report: inout ImportReport
    ) {
        importExerciseNotes(document.exerciseNotes ?? [], index: index, context: context, report: &report)
        importGymCards(document.gymCards ?? [], context: context)
        importCoachInteractions(document.coachInteractions ?? [], context: context)
        importPhotos(document.progressPhotos ?? [], context: photoContext, report: &report)
        importHealth(document.healthImports, context: healthContext, report: &report)
    }

    private static func importExerciseNotes(
        _ items: [BackupExerciseNote], index: ExerciseIndex, context: ModelContext,
        report: inout ImportReport
    ) {
        let existingIDs = Set(((try? context.fetch(FetchDescriptor<ExerciseNoteModel>())) ?? []).map(\.id))
        for item in items where !existingIDs.contains(item.id) {
            let exercise = index.find(seedID: item.exerciseSeedID, id: nil, name: item.exerciseName)
            context.insert(
                ExerciseNoteModel(
                    id: item.id, exerciseID: exercise?.id, text: item.text, scope: item.scope,
                    createdAt: item.createdAt, workoutID: item.workoutID
                )
            )
            report.exerciseNotesImported += 1
        }
    }

    private static func importGymCards(_ items: [BackupGymCard], context: ModelContext) {
        let existingIDs = Set(((try? context.fetch(FetchDescriptor<GymCardModel>())) ?? []).map(\.id))
        for item in items where !existingIDs.contains(item.id) {
            context.insert(
                GymCardModel(
                    id: item.id, name: item.name, value: item.value, symbology: item.symbology,
                    sortOrder: item.sortOrder, createdAt: item.createdAt, lastUsedAt: item.lastUsedAt
                )
            )
        }
    }

    private static func importCoachInteractions(
        _ items: [BackupCoachInteraction], context: ModelContext
    ) {
        let existing = (try? context.fetch(FetchDescriptor<CoachInteractionModel>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        for item in items where !existingIDs.contains(item.id) {
            context.insert(
                CoachInteractionModel(
                    id: item.id, rule: item.rule, fingerprint: item.fingerprint,
                    outcome: item.outcome, date: item.date
                )
            )
        }
    }

    /// Photos live in their own local-only store, so they need their own context and their own
    /// save. A row whose image didn't fit in the backup still restores its date, pose and notes.
    private static func importPhotos(
        _ items: [BackupProgressPhoto], context: ModelContext?, report: inout ImportReport
    ) {
        guard !items.isEmpty else { return }
        guard let context else {
            report.problems.append(
                "\(items.count) progress photos couldn't be restored: the photo store isn't available."
            )
            return
        }
        let existingIDs = Set(((try? context.fetch(FetchDescriptor<ProgressPhotoModel>())) ?? []).map(\.id))
        for item in items where !existingIDs.contains(item.id) {
            let data = item.imageBase64.flatMap { Data(base64Encoded: $0) }
            context.insert(
                ProgressPhotoModel(
                    id: item.id, date: item.date, pose: item.pose, imageData: data,
                    thumbnailData: data.flatMap(thumbnail(from:)),
                    bodyweightKg: item.bodyweightKg, notes: item.notes
                )
            )
            report.photosImported += 1
        }
        try? context.save()
    }

    /// The grid thumbnail, regenerated from the restored full-size JPEG rather than carried in the
    /// backup — it's derived data, and doubling the file size to store it would be wasteful.
    private static func thumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return PhotoProcessor.resized(image, longEdge: PhotoProcessor.thumbnailLongEdge)?
            .jpegData(compressionQuality: PhotoProcessor.thumbnailQuality)
    }

    /// The tombstones matter as much as the imported rows: without them a restore re-imports every
    /// Apple Health session the user has already deleted from History.
    private static func importHealth(
        _ item: BackupHealthImport?, context: ModelContext?, report: inout ImportReport
    ) {
        guard let item, !item.imported.isEmpty || !item.ignoredHealthKitIDs.isEmpty else { return }
        guard let context else {
            report.problems.append(
                "Apple Health import history couldn't be restored: the Health store isn't available."
            )
            return
        }
        let existing = (try? context.fetch(FetchDescriptor<ImportedHealthWorkoutModel>())) ?? []
        let existingKeys = Set(existing.map(\.healthKitID))
        for row in item.imported where !existingKeys.contains(row.healthKitID) {
            context.insert(
                ImportedHealthWorkoutModel(
                    id: row.id, healthKitID: row.healthKitID, title: row.title,
                    startedAt: row.startedAt, endedAt: row.endedAt, importedAt: row.importedAt
                )
            )
        }
        let ignored = (try? context.fetch(FetchDescriptor<IgnoredHealthWorkoutModel>())) ?? []
        let ignoredKeys = Set(ignored.map(\.healthKitID))
        for identifier in item.ignoredHealthKitIDs where !ignoredKeys.contains(identifier) {
            context.insert(IgnoredHealthWorkoutModel(healthKitID: identifier))
            report.healthTombstonesImported += 1
        }
        try? context.save()
    }
}
