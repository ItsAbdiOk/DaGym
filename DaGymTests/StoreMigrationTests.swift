import Foundation
import SwiftData
import Testing

@testable import DaGym

@Suite("Legacy store migration into the App Group container")
struct StoreMigrationTests {
    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var storeFileName: String {
        ModelConfiguration(schema: Schema(DaGymSchema.models)).url.lastPathComponent
    }

    @Test("moves the store plus -wal/-shm sidecars and deletes the legacy copies")
    func movesStoreAndSidecars() throws {
        let legacy = tempDirectory()
        let destination = tempDirectory()
        let schema = Schema(DaGymSchema.models)
        let fileName = storeFileName

        for suffix in ["", "-wal", "-shm"] {
            try Data("legacy\(suffix)".utf8).write(to: legacy.appendingPathComponent(fileName + suffix))
        }

        StoreMigration.moveLegacyStoreIfNeeded(
            schema: schema, legacyDirectory: legacy, destinationDirectory: destination
        )

        for suffix in ["", "-wal", "-shm"] {
            let destinationPath = destination.appendingPathComponent(fileName + suffix).path
            let legacyPath = legacy.appendingPathComponent(fileName + suffix).path
            #expect(FileManager.default.fileExists(atPath: destinationPath))
            #expect(!FileManager.default.fileExists(atPath: legacyPath))
        }
    }

    @Test("is a no-op when the destination already has a store")
    func noOpWhenDestinationExists() throws {
        let legacy = tempDirectory()
        let destination = tempDirectory()
        let schema = Schema(DaGymSchema.models)
        let fileName = storeFileName

        try Data("legacy".utf8).write(to: legacy.appendingPathComponent(fileName))
        try Data("existing-destination".utf8).write(to: destination.appendingPathComponent(fileName))

        StoreMigration.moveLegacyStoreIfNeeded(
            schema: schema, legacyDirectory: legacy, destinationDirectory: destination
        )

        let destinationData = try Data(contentsOf: destination.appendingPathComponent(fileName))
        #expect(String(bytes: destinationData, encoding: .utf8) == "existing-destination")
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent(fileName).path))
    }

    @Test("is a no-op when there's nothing to migrate")
    func noOpWhenNothingToMigrate() throws {
        let legacy = tempDirectory()
        let destination = tempDirectory()
        let schema = Schema(DaGymSchema.models)

        StoreMigration.moveLegacyStoreIfNeeded(
            schema: schema, legacyDirectory: legacy, destinationDirectory: destination
        )

        let destinationPath = destination.appendingPathComponent(storeFileName).path
        #expect(!FileManager.default.fileExists(atPath: destinationPath))
    }
}
