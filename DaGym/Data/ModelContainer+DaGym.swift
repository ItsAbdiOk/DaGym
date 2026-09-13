import Foundation
import SwiftData

/// The full DaGym persistence schema, in one place so every container and
/// migration references the same list.
enum DaGymSchema {
    static let models: [any PersistentModel.Type] = [
        ExerciseModel.self,
        RoutineModel.self,
        RoutineExerciseModel.self,
        PlannedSetModel.self,
        WorkoutModel.self,
        WorkoutExerciseModel.self,
        SetLogModel.self,
        BodyMeasurementModel.self,
        PersonalRecordModel.self,
        EquipmentProfileModel.self,
        ScheduleModel.self,
        AchievementModel.self,
        ProgressPhotoModel.self
    ]

    /// Models that live in the separate, always-local photo store (see
    /// `ModelContainer.dagym(...)`), not the main CloudKit-syncable one.
    static let photoModels: [any PersistentModel.Type] = [ProgressPhotoModel.self]

    /// Every other model — the ones the main configuration owns.
    static var mainModels: [any PersistentModel.Type] {
        let photoIDs = Set(photoModels.map(ObjectIdentifier.init))
        return models.filter { !photoIDs.contains(ObjectIdentifier($0)) }
    }
}

extension ModelContainer {
    /// The app's model container. `inMemory` is for tests and previews so nothing touches disk.
    /// `cloudKitEnabled` mirrors `Preferences.iCloudSyncEnabled` (plan.md §6.3): when `true` the
    /// store syncs through the user's private CloudKit database; the store itself lives in the
    /// App Group container so the widgets extension's App Group entitlement can, in principle,
    /// share it (the widgets read a `WidgetSnapshot` instead — see `WidgetSnapshotWriter` — but
    /// the shared location is also what makes a future watch/App Group read possible).
    ///
    /// If CloudKit itself throws (no iCloud account, simulator without sign-in, missing
    /// entitlement on an ad-hoc build), the caller should retry with `cloudKitEnabled: false` —
    /// see `AppRootContainer.resolveContainer()`.
    static func dagym(inMemory: Bool = false, cloudKitEnabled: Bool = true) throws -> ModelContainer {
        let schema = Schema(DaGymSchema.models)
        let mainSchema = Schema(DaGymSchema.mainModels)
        let photoSchema = Schema(DaGymSchema.photoModels)
        guard !inMemory else {
            // `.none` is explicit: the default (`.automatic`) starts CloudKit mirroring whenever
            // the entitlement is present, which is what tests and previews must never do.
            // Distinct names matter: two unnamed in-memory stores collapse into one and inserts
            // then fail with "store does not contain the object's entity".
            let mainConfiguration = ModelConfiguration(
                "DaGymMain", schema: mainSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
            let photoConfiguration = ModelConfiguration(
                "DaGymPhotos", schema: photoSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [mainConfiguration, photoConfiguration])
        }
        StoreMigration.moveLegacyStoreIfNeeded(schema: schema)
        let database: ModelConfiguration.CloudKitDatabase = cloudKitEnabled
            ? .private("iCloud.dev.abdirahmanmohamed.dagym") : .none
        let mainConfiguration = ModelConfiguration(
            schema: mainSchema, url: StoreMigration.storeURL(schema: schema), cloudKitDatabase: database
        )
        // Progress photos (plan.md §6.4 "don't sync photos"): a separate, always-local store —
        // `cloudKitDatabase: .none` is a per-configuration setting, so this is the only way to
        // keep photos off iCloud while the rest of the app still syncs.
        let photoConfiguration = ModelConfiguration(
            schema: photoSchema, url: StoreMigration.photoStoreURL(), cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [mainConfiguration, photoConfiguration])
    }
}

/// Moves the on-disk SwiftData store from its pre-App-Group default location into the App Group
/// container the first time this runs, so upgrading users keep their data. A no-op on a fresh
/// install (nothing to migrate) and once the destination already has a store.
enum StoreMigration {
    static let appGroupID = "group.dev.abdirahmanmohamed.dagym"

    /// Where the store lives now: the App Group container, falling back to the default
    /// Application Support location if the App Group isn't available (e.g. the entitlement is
    /// missing on an ad-hoc build) — the app must still start.
    static func storeURL(schema: Schema) -> URL {
        let fileName = defaultConfiguration(schema: schema).url.lastPathComponent
        return containerDirectory().appendingPathComponent(fileName)
    }

    /// Where the always-local progress-photo store lives — its own file, in the same App Group
    /// directory as the main store, so it never touches CloudKit no matter what
    /// `iCloudSyncEnabled` is set to.
    static func photoStoreURL() -> URL {
        containerDirectory().appendingPathComponent("DaGymPhotos.sqlite")
    }

    /// Copies `<name>.store` plus its `-wal`/`-shm` sidecar files from the legacy location to the
    /// App Group container, verifies the copy landed, then deletes the legacy files — so a crash
    /// mid-move can never lose data (worst case: the legacy copy survives and gets deleted on the
    /// next successful launch instead).
    static func moveLegacyStoreIfNeeded(
        schema: Schema, fileManager: FileManager = .default,
        legacyDirectory: URL? = nil, destinationDirectory: URL? = nil
    ) {
        let legacyURL = defaultConfiguration(schema: schema).url
        let legacyDirectory = legacyDirectory ?? legacyURL.deletingLastPathComponent()
        let destinationDirectory = destinationDirectory ?? containerDirectory()
        let fileName = legacyURL.lastPathComponent
        let legacyStore = legacyDirectory.appendingPathComponent(fileName)
        let destinationStore = destinationDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: legacyStore.path) else { return }
        guard !fileManager.fileExists(atPath: destinationStore.path) else { return }
        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            for suffix in Self.sidecarSuffixes {
                try copyIfExists(
                    fileName: fileName + suffix, from: legacyDirectory, to: destinationDirectory,
                    fileManager: fileManager
                )
            }
            guard fileManager.fileExists(atPath: destinationStore.path) else { return }
            for suffix in Self.sidecarSuffixes {
                try? fileManager.removeItem(at: legacyDirectory.appendingPathComponent(fileName + suffix))
            }
        } catch {
            let message = error.localizedDescription
            storeLogger.error("Store migration to App Group failed: \(message, privacy: .public)")
        }
    }

    private static let sidecarSuffixes = ["", "-wal", "-shm"]

    private static func copyIfExists(
        fileName: String, from sourceDirectory: URL, to destinationDirectory: URL, fileManager: FileManager
    ) throws {
        let source = sourceDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: source.path) else { return }
        let destination = destinationDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    /// The default (pre-App-Group) store location SwiftData would have chosen, exactly as the
    /// original `ModelContainer.dagym(inMemory:)` did before this change — asking
    /// `ModelConfiguration` rather than hardcoding a path avoids guessing its naming scheme.
    private static func defaultConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema)
    }

    private static func containerDirectory() -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
    }
}
