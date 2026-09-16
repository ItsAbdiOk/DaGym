import Foundation
import GymCore
import SwiftData
import Testing
import UIKit

@testable import DaGym

/// The two local-only sections of a restore — progress photos and the Apple Health import
/// bookkeeping — each land in their own store, dedupe by id, and are reported (not dropped) when
/// the caller has no such store to put them in.
@MainActor
@Suite("Backup restore: photos and Health bookkeeping")
struct BackupImportExtrasTests {
    private func photoContext() throws -> ModelContext {
        ModelContext(try ModelContainer.dagymPhotos(inMemory: true))
    }

    private func healthContext() throws -> ModelContext {
        ModelContext(try ModelContainer.dagymHealth(inMemory: true))
    }

    private func document(
        photos: [BackupProgressPhoto] = [], health: BackupHealthImport? = nil
    ) -> BackupDocument {
        BackupDocument(
            exportedAt: Date(), appVersion: "1.0", preferences: BackupPreferences(),
            progressPhotos: photos, healthImports: health
        )
    }

    /// A real 8×8 JPEG so the restore can decode it and derive a thumbnail.
    private static var jpegBase64: String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 0.9)?.base64EncodedString() ?? ""
    }

    @Test("a photo with an image restores it plus a regenerated thumbnail; one without keeps its metadata")
    func photosRestoreWithDerivedThumbnail() throws {
        let withImage = UUID()
        let metadataOnly = UUID()
        let document = document(photos: [
            BackupProgressPhoto(
                id: withImage, date: Date(timeIntervalSince1970: 1_000), pose: "side", bodyweightKg: 81.5,
                notes: "cut week 3", imageBase64: Self.jpegBase64
            ),
            BackupProgressPhoto(id: metadataOnly, date: Date(timeIntervalSince1970: 2_000), pose: "back")
        ])
        let photos = try photoContext()
        let main = try makeContext()
        let report = BackupService.import(document: document, context: main, photoContext: photos)
        #expect(report.photosImported == 2)
        #expect(report.problems.isEmpty)

        let rows = try photos.fetch(FetchDescriptor<ProgressPhotoModel>())
        let restored = try #require(rows.first { $0.id == withImage })
        #expect(restored.pose == "side")
        #expect(restored.bodyweightKg == 81.5)
        #expect(restored.notes == "cut week 3")
        #expect(restored.imageData != nil)
        #expect(restored.thumbnailData != nil)
        let bare = try #require(rows.first { $0.id == metadataOnly })
        #expect(bare.imageData == nil)
        #expect(bare.thumbnailData == nil)
        #expect(bare.pose == "back")
    }

    @Test("restoring the same photos twice adds nothing the second time")
    func photosDedupeByID() throws {
        let document = document(photos: [BackupProgressPhoto(id: UUID(), date: Date())])
        let photos = try photoContext()
        let main = try makeContext()
        _ = BackupService.import(document: document, context: main, photoContext: photos)
        let second = BackupService.import(document: document, context: main, photoContext: photos)
        #expect(second.photosImported == 0)
        #expect(try photos.fetch(FetchDescriptor<ProgressPhotoModel>()).count == 1)
    }

    /// The Settings path generates thumbnails off the main actor first; the import must use
    /// those rather than decode the JPEG again on the main actor.
    @Test("thumbnails handed in are used as-is; the off-main generator matches the inline one")
    func precomputedThumbnailsAreUsed() throws {
        let id = UUID()
        let photo = BackupProgressPhoto(id: id, date: Date(), imageBase64: Self.jpegBase64)
        let generated = BackupService.thumbnails(for: [photo])
        #expect(generated[id] != nil)
        #expect(BackupService.thumbnails(for: [BackupProgressPhoto(id: UUID(), date: Date())]).isEmpty)

        let photos = try photoContext()
        let marker = Data("precomputed".utf8)
        let report = BackupService.import(
            document: document(photos: [photo]), context: try makeContext(), photoContext: photos,
            thumbnails: [id: marker]
        )
        #expect(report.photosImported == 1)
        let row = try #require(try photos.fetch(FetchDescriptor<ProgressPhotoModel>()).first)
        #expect(row.thumbnailData == marker)
    }

    /// History and Home redraw on `changeToken`; an import that saved through the context
    /// alone never bumped it, so the restored rows stayed invisible until an unrelated save.
    @Test("importing on the live store bumps its changeToken")
    func importOnLiveStoreBumpsChangeToken() throws {
        let store = WorkoutStore(context: try makeContext())
        let before = store.changeToken
        let document = document(photos: [BackupProgressPhoto(id: UUID(), date: Date())])
        BackupService.import(
            document: document, context: store.context, photoContext: store.photoContext, store: store
        )
        #expect(store.changeToken > before)
    }

    @Test("the async Settings entry point restores photos and reports like the sync one")
    func asyncImportRestoresPhotos() async throws {
        let store = WorkoutStore(context: try makeContext())
        let id = UUID()
        let photo = BackupProgressPhoto(id: id, date: Date(), imageBase64: Self.jpegBase64)
        let report = await BackupService.import(
            document: document(photos: [photo]), store: store, preferences: Preferences()
        )
        #expect(report.photosImported == 1)
        let photos = try #require(store.photoContext)
        let row = try #require(try photos.fetch(FetchDescriptor<ProgressPhotoModel>()).first)
        #expect(row.id == id)
        #expect(row.thumbnailData != nil)
    }

    @Test("an unreadable image restores the row without image or thumbnail rather than failing")
    func garbageImageKeepsTheRow() throws {
        let id = UUID()
        let garbage = Data("not a jpeg".utf8).base64EncodedString()
        let document = document(photos: [BackupProgressPhoto(id: id, date: Date(), imageBase64: garbage)])
        let photos = try photoContext()
        let main = try makeContext()
        let report = BackupService.import(document: document, context: main, photoContext: photos)
        #expect(report.photosImported == 1)
        let row = try #require(try photos.fetch(FetchDescriptor<ProgressPhotoModel>()).first)
        #expect(row.imageData == Data("not a jpeg".utf8))
        #expect(row.thumbnailData == nil)
    }

    @Test("photos in the file but no photo store: counted as a problem, nothing imported")
    func photosWithoutStoreAreReported() throws {
        let document = document(photos: [
            BackupProgressPhoto(id: UUID(), date: Date()), BackupProgressPhoto(id: UUID(), date: Date())
        ])
        let report = BackupService.import(document: document, context: try makeContext())
        #expect(report.photosImported == 0)
        #expect(report.problems
            == ["2 progress photos couldn't be restored: the photo store isn't available."])
    }

    @Test("an empty photo list with no photo store is not a problem")
    func noPhotosNoProblem() throws {
        let report = BackupService.import(document: document(photos: []), context: try makeContext())
        #expect(report.problems.isEmpty)
    }

    @Test("Health imports restore both the imported rows and the delete tombstones, keyed by HealthKit id")
    func healthRowsAndTombstones() throws {
        let health = try healthContext()
        health.insert(ImportedHealthWorkoutModel(healthKitID: "hk-already", title: "Old"))
        health.insert(IgnoredHealthWorkoutModel(healthKitID: "hk-ignored-already"))
        try health.save()
        let now = Date(timeIntervalSince1970: 5_000)
        let document = document(health: BackupHealthImport(
            imported: [
                BackupImportedHealthWorkout(
                    id: UUID(), healthKitID: "hk-already", title: "Dup", startedAt: now, endedAt: now,
                    importedAt: now
                ),
                BackupImportedHealthWorkout(
                    id: UUID(), healthKitID: "hk-new", title: "Watch strength", startedAt: now,
                    endedAt: now.addingTimeInterval(1_800), importedAt: now
                )
            ],
            ignoredHealthKitIDs: ["hk-ignored-already", "hk-deleted-1", "hk-deleted-2"]
        ))
        let main = try makeContext()
        let report = BackupService.import(document: document, context: main, healthContext: health)
        #expect(report.healthTombstonesImported == 2)
        #expect(report.problems.isEmpty)

        let imported = try health.fetch(FetchDescriptor<ImportedHealthWorkoutModel>())
        #expect(Set(imported.map(\.healthKitID)) == ["hk-already", "hk-new"])
        #expect(imported.first { $0.healthKitID == "hk-already" }?.title == "Old")
        let ignored = try health.fetch(FetchDescriptor<IgnoredHealthWorkoutModel>())
        #expect(Set(ignored.map(\.healthKitID)) == ["hk-ignored-already", "hk-deleted-1", "hk-deleted-2"])
    }

    @Test("Health bookkeeping in the file but no Health store: reported, not silently dropped")
    func healthWithoutStoreIsReported() throws {
        let document = document(health: BackupHealthImport(ignoredHealthKitIDs: ["hk-deleted"]))
        let report = BackupService.import(document: document, context: try makeContext())
        #expect(report.healthTombstonesImported == 0)
        #expect(report.problems == [
            "Apple Health import history couldn't be restored: the Health store isn't available."
        ])
    }

    @Test("an empty Health section with no Health store is not a problem")
    func emptyHealthSectionIsFine() throws {
        let document = document(health: BackupHealthImport())
        let report = BackupService.import(document: document, context: try makeContext())
        #expect(report.problems.isEmpty)
    }
}
