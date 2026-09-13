import Foundation
import SwiftData
import os

private let seedLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "seeder")

/// Loads `Resources/Seed/exercises.json` into the store on first launch.
/// Idempotent: re-running only inserts exercises whose `seedID` is missing.
/// When the bundled seed's `version` is newer than the last applied version
/// (persisted in UserDefaults under `seedVersion`), existing rows have their
/// instructions/provenance fields refreshed without duplicating rows.
@MainActor
enum ExerciseSeeder {
    static let seedVersionKey = "seedVersion"

    struct SeedFile: Decodable {
        var version: Int
        var source: String
        var exercises: [SeedExercise]
    }

    struct SeedExercise: Decodable {
        var id: String
        var name: String
        var primary: [String]
        var secondary: [String]
        var equipment: String
        var mechanic: String?
        var loggingStyle: String
        var isPerSide: Bool
        var bar: String?
        var incrementKg: Double
        var restSeconds: Int
        var instructions: String?
        var source: String?
        var sourceURL: String?
        var licence: String?
        var authors: [String]?
    }

    enum SeederError: Error {
        case resourceNotFound
    }

    /// Inserts every seeded exercise not already present, keyed by `seedID`.
    /// Refreshes existing rows' provenance fields when the seed version bumped.
    static func seedIfNeeded(
        context: ModelContext, bundle: Bundle = .main, defaults: UserDefaults = .standard
    ) {
        do {
            let data = try loadSeedData(bundle: bundle)
            let seed = try JSONDecoder().decode(SeedFile.self, from: data)
            try insertMissing(seed.exercises, into: context)
            let appliedVersion = defaults.integer(forKey: seedVersionKey)
            if seed.version > appliedVersion {
                try updateExisting(seed.exercises, in: context)
                defaults.set(seed.version, forKey: seedVersionKey)
            }
        } catch {
            seedLogger.error("Exercise seeding failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func insertMissing(_ items: [SeedExercise], into context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<ExerciseModel>())
        var existingIDs = Set(existing.compactMap(\.seedID))
        var insertedCount = 0
        for item in items where !existingIDs.contains(item.id) {
            let model = ExerciseModel(
                seedID: item.id, name: item.name, primaryMuscles: item.primary,
                secondaryMuscles: item.secondary, equipment: item.equipment, mechanic: item.mechanic,
                loggingStyle: item.loggingStyle, isPerSide: item.isPerSide, barType: item.bar,
                incrementKg: item.incrementKg, restSeconds: item.restSeconds,
                instructions: item.instructions ?? "", dataSource: item.source ?? "",
                sourceURL: item.sourceURL ?? "", licence: item.licence ?? "",
                authors: item.authors ?? []
            )
            context.insert(model)
            existingIDs.insert(item.id)
            insertedCount += 1
        }
        if insertedCount > 0 {
            try context.save()
            seedLogger.info("Seeded \(insertedCount, privacy: .public) exercises")
        }
    }

    /// Updates instructions/provenance on rows that already exist, matched by
    /// `seedID`. Never inserts or duplicates rows.
    private static func updateExisting(_ items: [SeedExercise], in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<ExerciseModel>())
        var bySeedID: [String: ExerciseModel] = [:]
        for model in existing {
            if let seedID = model.seedID {
                bySeedID[seedID] = model
            }
        }
        var updatedCount = 0
        for item in items {
            guard let model = bySeedID[item.id] else { continue }
            if let instructions = item.instructions, !instructions.isEmpty {
                model.instructions = instructions
            }
            if let source = item.source { model.dataSource = source }
            if let sourceURL = item.sourceURL { model.sourceURL = sourceURL }
            if let licence = item.licence { model.licence = licence }
            if let authors = item.authors { model.authors = authors }
            updatedCount += 1
        }
        if updatedCount > 0 {
            try context.save()
            seedLogger.info("Updated \(updatedCount, privacy: .public) exercises to newer seed version")
        }
    }

    /// The seed JSON lives at `Resources/Seed/exercises.json`. Swift Testing
    /// structs don't have a `Bundle(for:)` peer, so we try the passed-in
    /// bundle, then `Bundle(identifier:)`, then every loaded bundle.
    private static func loadSeedData(bundle: Bundle) throws -> Data {
        if let url = seedURL(in: bundle) {
            return try Data(contentsOf: url)
        }
        if let named = Bundle(identifier: "dev.abdirahmanmohamed.dagym"), let url = seedURL(in: named) {
            return try Data(contentsOf: url)
        }
        for candidate in Bundle.allBundles {
            if let url = seedURL(in: candidate) {
                return try Data(contentsOf: url)
            }
        }
        throw SeederError.resourceNotFound
    }

    private static func seedURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "exercises", withExtension: "json", subdirectory: "Seed")
            ?? bundle.url(forResource: "exercises", withExtension: "json")
    }
}
