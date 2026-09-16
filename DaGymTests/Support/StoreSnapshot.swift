import Foundation
import SwiftData
import Testing

@testable import DaGym

/// A store a past build wrote (`DaGymTests/Fixtures/Stores/<sha>/DaGym.store`), staged into a
/// throwaway directory and opened with the *current* on-disk configuration — exactly what
/// happens on a lifter's phone the first time the new build launches over their old data.
/// `expected.json` next to each fixture is what the snapshot writer counted before it closed
/// the store; the harness proves nothing in it went missing.
@MainActor
struct StoreSnapshot {
    /// Every snapshot on disk, oldest build first. Add the new sha here after producing its
    /// fixture (see the top of `UpgradePathTests.swift`).
    nonisolated static let shas = ["0bf5773", "5c7ce8d"]

    /// The counts and values the writer recorded; keys match `expected.json`.
    struct Expected: Decodable {
        var exerciseSeedVersion: Int
        var exercises: Int
        var routines: Int
        var routineExercises: Int
        var plannedSets: Int
        var workouts: Int
        var workoutExercises: Int
        var sets: Int
        var bodyMeasurements: Int
        var exerciseNotes: Int
        var programs: Int
        var programWeeks: Int
        var schedules: Int
        var equipmentProfiles: Int
        var personalRecords: Int
        var personalRecordEvents: Int
        var totalVolumeKg: Double
        var totalSetsDone: Int
        var bodyweightKg: Double
        var noteText: String
        var keptRoutineNames: [String]
        var prunedRoutineNames: [String]

        static let none = Expected(
            exerciseSeedVersion: 0, exercises: 0, routines: 0, routineExercises: 0, plannedSets: 0,
            workouts: 0, workoutExercises: 0, sets: 0, bodyMeasurements: 0, exerciseNotes: 0,
            programs: 0, programWeeks: 0, schedules: 0, equipmentProfiles: 0, personalRecords: 0,
            personalRecordEvents: 0, totalVolumeKg: 0, totalSetsDone: 0, bodyweightKg: 0, noteText: "",
            keptRoutineNames: [], prunedRoutineNames: []
        )
    }

    let sha: String
    let expected: Expected
    /// The App Group stand-in the store is opened from; the legacy directory beside it stays
    /// empty so `StoreMigration.moveLegacyStoreIfNeeded` has nothing to move.
    private let directory: URL
    private let legacyDirectory: URL

    /// Copies the fixture into a fresh temp directory under the name the current build's
    /// configuration expects.
    static func stage(_ sha: String) throws -> StoreSnapshot {
        let bundle = Bundle(for: StoreSnapshotAnchor.self)
        let subdirectory = "Fixtures/Stores/\(sha)"
        let fixture = try #require(
            bundle.url(forResource: "DaGym", withExtension: "store", subdirectory: subdirectory),
            "No fixture for \(sha) in the test bundle — is DaGymTests/Fixtures a folder reference?"
        )
        let expectedURL = try #require(
            bundle.url(forResource: "expected", withExtension: "json", subdirectory: subdirectory)
        )
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: expectedURL))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dagym-upgrade-\(sha)-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("group", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let snapshot = StoreSnapshot(
            sha: sha, expected: expected, directory: directory, legacyDirectory: legacyDirectory
        )
        try FileManager.default.copyItem(at: fixture, to: snapshot.storeURL)
        return snapshot
    }

    /// No fixture at all: an empty directory the current build seeds from scratch, for the
    /// trivial current → current case. `expected` is all zeros and unused.
    static func fresh() throws -> StoreSnapshot {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dagym-upgrade-fresh-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("group", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        return StoreSnapshot(
            sha: "current", expected: .none, directory: directory, legacyDirectory: legacyDirectory
        )
    }

    /// The store file the current configuration will open — `StoreMigration.storeURL` with the
    /// App Group redirected at `directory`.
    private var storeURL: URL {
        withOverrides { StoreMigration.storeURL(schema: DaGymSchema.mainSchema) }
    }

    /// Opens the staged store the way `ContainerProvider` does without iCloud: the real
    /// on-disk configuration, CloudKit off. Throws whatever `ModelContainer` throws — the
    /// schema safety-net test turns that into a named failure.
    func openContainer() throws -> ModelContainer {
        try withOverrides { try ModelContainer.dagym(cloudKitEnabled: false) }
    }

    /// A `WorkoutStore` over the container's main context with throwaway photo and Health
    /// stores, as `ContainerProvider.store` builds it.
    func makeStore(_ container: ModelContainer) throws -> WorkoutStore {
        WorkoutStore(
            context: container.mainContext,
            photoContext: ModelContext(try ModelContainer.dagymPhotos(inMemory: true)),
            healthContext: ModelContext(try ModelContainer.dagymHealth(inMemory: true))
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    /// The store-location overrides are process-wide statics, so they are set only for the
    /// synchronous span of one call and put back straight after — no `await` in between means
    /// no other main-actor test can observe them.
    private func withOverrides<T>(_ body: () throws -> T) rethrows -> T {
        let previous = (StoreMigration.containerDirectoryOverride, StoreMigration.legacyDirectoryOverride)
        StoreMigration.containerDirectoryOverride = directory
        StoreMigration.legacyDirectoryOverride = legacyDirectory
        defer {
            StoreMigration.containerDirectoryOverride = previous.0
            StoreMigration.legacyDirectoryOverride = previous.1
        }
        return try body()
    }
}

/// Swift Testing structs have no `Bundle(for:)` peer; the fixtures live in the test bundle, so
/// the lookup needs a class defined in it.
private final class StoreSnapshotAnchor {}

// MARK: - What a launch must leave behind

/// Row counts and the "last written" stamps that a second launch must not move. Two of these
/// taken either side of `LaunchSeeding.run` being equal is the proof that launch is a no-op on
/// a store that is already current.
struct StoreFingerprint: Equatable {
    var counts: [String: Int]
    var seedStateUpdatedAt: Date
    var routineUpdatedAts: [UUID: Date]
    var scheduleUpdatedAt: Date?
    var workoutTotals: [UUID: Double]

    @MainActor
    init(context: ModelContext) throws {
        counts = try Self.counts(in: context)
        seedStateUpdatedAt = SeedState.row(in: context).updatedAt
        let routines = try context.fetch(FetchDescriptor<RoutineModel>())
        routineUpdatedAts = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0.updatedAt) })
        scheduleUpdatedAt = try context.fetch(FetchDescriptor<ScheduleModel>()).first?.updatedAt
        let workouts = try context.fetch(FetchDescriptor<WorkoutModel>())
        workoutTotals = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.volumeKg) })
    }

    /// One count per main-store model, keyed like `expected.json`.
    @MainActor
    static func counts(in context: ModelContext) throws -> [String: Int] {
        [
            "exercises": try context.fetchCount(FetchDescriptor<ExerciseModel>()),
            "routines": try context.fetchCount(FetchDescriptor<RoutineModel>()),
            "routineExercises": try context.fetchCount(FetchDescriptor<RoutineExerciseModel>()),
            "plannedSets": try context.fetchCount(FetchDescriptor<PlannedSetModel>()),
            "workouts": try context.fetchCount(FetchDescriptor<WorkoutModel>()),
            "workoutExercises": try context.fetchCount(FetchDescriptor<WorkoutExerciseModel>()),
            "sets": try context.fetchCount(FetchDescriptor<SetLogModel>()),
            "bodyMeasurements": try context.fetchCount(FetchDescriptor<BodyMeasurementModel>()),
            "exerciseNotes": try context.fetchCount(FetchDescriptor<ExerciseNoteModel>()),
            "programs": try context.fetchCount(FetchDescriptor<ProgramModel>()),
            "programWeeks": try context.fetchCount(FetchDescriptor<ProgramWeekModel>()),
            "schedules": try context.fetchCount(FetchDescriptor<ScheduleModel>()),
            "equipmentProfiles": try context.fetchCount(FetchDescriptor<EquipmentProfileModel>()),
            "personalRecords": try context.fetchCount(FetchDescriptor<PersonalRecordModel>()),
            "personalRecordEvents": try context.fetchCount(FetchDescriptor<PersonalRecordEventModel>()),
            "seedStates": try context.fetchCount(FetchDescriptor<SeedStateModel>())
        ]
    }
}
