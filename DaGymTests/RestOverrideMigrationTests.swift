import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Seed v4 moved a seeded exercise's *unedited* rest from the seed's number to 0 ("use
/// Settings → Default rest"). Everything written before that — a backup file, a copy seeded by
/// a device still on v3 — carries the seed's number for a row the lifter never touched, and
/// must not arrive on a v4 store as a permanent per-exercise override.
@MainActor
@Suite("Rest override migration", .serialized)
struct RestOverrideMigrationTests {
    private static let benchSeedID = "Barbell_Bench_Press_-_Medium_Grip"
    private static let squatSeedID = "Barbell_Squat"

    private func seeded(_ seedID: String, in context: ModelContext) throws -> ExerciseModel {
        try #require(try context.fetch(FetchDescriptor<ExerciseModel>()).first { $0.seedID == seedID })
    }

    private func seedRest(_ seedID: String) throws -> Int {
        try #require(try ExerciseSeeder.loadSeed().exercises.first { $0.id == seedID }).restSeconds
    }

    @Test("restoring a pre-v4 backup keeps the favourite but not the seed's rest as an override")
    func legacyBackupRestIsNotAnOverride() throws {
        let context = try makeContext(seed: .exercises)
        let bench = try seeded(Self.benchSeedID, in: context)
        let squat = try seeded(Self.squatSeedID, in: context)
        // Written last week: favourited, otherwise untouched — so rest is the seed's number.
        let favourited = BackupExercise(
            id: UUID(), seedID: Self.benchSeedID, name: bench.name, isFavorite: true,
            incrementKg: bench.incrementKg, restSeconds: try seedRest(Self.benchSeedID)
        )
        // A rest the lifter really did change is still an override.
        let edited = BackupExercise(
            id: UUID(), seedID: Self.squatSeedID, name: squat.name,
            incrementKg: squat.incrementKg, restSeconds: 200
        )
        let document = BackupDocument(
            exportedAt: Date(), appVersion: "1.0", exercises: [favourited, edited],
            preferences: BackupPreferences()
        )
        BackupService.import(document: document, context: context)
        #expect(bench.isFavorite)
        #expect(bench.restSeconds == 0, "the seed's own rest became a per-exercise override")
        #expect(squat.restSeconds == 200)
    }

    @Test("a copy seeded by a v3 device folds without carrying the seed's rest onto the survivor")
    func legacyCopyRestIsNotMerged() throws {
        let context = try makeContext(seed: .exercises)
        let bench = try seeded(Self.benchSeedID, in: context)
        let remote = ExerciseModel(
            seedID: bench.seedID, name: bench.name, primaryMuscles: bench.primaryMuscles,
            equipment: bench.equipment, loggingStyle: bench.loggingStyle,
            restSeconds: try seedRest(Self.benchSeedID),
            createdAt: bench.createdAt.addingTimeInterval(60)
        )
        context.insert(remote)
        try context.save()
        #expect(ExerciseSeeder.dedupe(in: context) > 0)
        #expect(bench.restSeconds == 0, "a v3 copy's unedited rest became an override on the survivor")
    }

    @Test("the rest migration runs for a store coming from v3, not on every later seed bump")
    func restMigrationIsOneShot() throws {
        let context = try makeContext(seed: .exercises)
        let bench = try seeded(Self.benchSeedID, in: context)
        let seedRest = try seedRest(Self.benchSeedID)
        let items = try ExerciseSeeder.loadSeed().exercises
        // The lifter deliberately set Bench to exactly the seed's number after v4.
        bench.restSeconds = seedRest
        try ExerciseSeeder.updateExisting(items, from: ExerciseSeeder.restMigrationVersion, in: context)
        #expect(bench.restSeconds == seedRest, "a later seed bump flipped an intentional rest to default")
        // Coming from v3 it is unedited rest, and moves to "use the default".
        try ExerciseSeeder.updateExisting(items, from: ExerciseSeeder.restMigrationVersion - 1, in: context)
        #expect(bench.restSeconds == 0)
    }
}
