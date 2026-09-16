import Foundation
import SwiftData
import Testing
@testable import DaGym

/// The on-disk container is what ships; the in-memory one is what tests normally use. This
/// pins the two-store (main + photos) configuration against the "store does not contain the
/// object's entity" crash that only appeared on a real device.
@Suite("On-disk model container", .serialized)
@MainActor
struct OnDiskContainerTests {
    @Test("main and photo stores accept inserts and reopen with the data")
    func twoStoresRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dagym-ondisk-\(UUID().uuidString)", isDirectory: true)
        let legacyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dagym-ondisk-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        StoreMigration.containerDirectoryOverride = directory
        // Without this, `dagym(cloudKitEnabled:false)`'s legacy-migration check falls back to the
        // test host's real Application Support directory (T7) — on a simulator that ever ran a
        // pre-App-Group build, this test would move (then delete) the developer's actual store.
        StoreMigration.legacyDirectoryOverride = legacyDirectory
        defer {
            StoreMigration.containerDirectoryOverride = nil
            StoreMigration.legacyDirectoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: legacyDirectory)
        }

        do {
            let context = ModelContext(try ModelContainer.dagym(cloudKitEnabled: false))
            context.insert(ExerciseModel(name: "Bench Press", primaryMuscles: ["chest"]))
            try context.save()
            let photoContext = ModelContext(try ModelContainer.dagymPhotos())
            photoContext.insert(ProgressPhotoModel(pose: "front"))
            try photoContext.save()
        }

        let context = ModelContext(try ModelContainer.dagym(cloudKitEnabled: false))
        let photoContext = ModelContext(try ModelContainer.dagymPhotos())
        #expect(try context.fetchCount(FetchDescriptor<ExerciseModel>()) == 1)
        #expect(try photoContext.fetchCount(FetchDescriptor<ProgressPhotoModel>()) == 1)
        // Seeding + a first fetch on a fresh on-disk store is the exact path that trapped on device.
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context, photoContext: photoContext)
        RoutineSeeder.seedAll(store: store)
        #expect(store.routines().count == RoutineSeeder.starterIDs.count)
    }
}
