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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        StoreMigration.containerDirectoryOverride = directory
        defer {
            StoreMigration.containerDirectoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
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
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        #expect(store.routines().count == 3)
    }
}
