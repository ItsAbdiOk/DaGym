import Foundation
import SwiftData
import Testing
@testable import DaGym

/// One container per process: the app shell and the in-process App Intents must get the same
/// instance, and the intents must honour the iCloud toggle rather than opening a second,
/// CloudKit-mirrored container on the same files.
@Suite("ContainerProvider", .serialized)
@MainActor
struct ContainerProviderTests {
    @Test("the same main container, photo container and store come back on every call")
    func returnsOneInstance() throws {
        let provider = ContainerProvider(inMemory: true)
        let first = try #require(provider.main(cloudKitEnabled: true))
        let second = try #require(provider.main(cloudKitEnabled: false))
        #expect(first === second)
        #expect(provider.mainResolution == .inMemory)

        let photos = try #require(provider.photos())
        #expect(photos === provider.photos())

        let store = try #require(provider.store(cloudKitEnabled: true))
        #expect(store === provider.store(cloudKitEnabled: true))
        #expect(store.context === first.mainContext)
        #expect(store.photoContext != nil)
    }

    @Test("with iCloud sync off the on-disk container is local, not CloudKit-mirrored")
    func syncOffMeansLocalStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dagym-provider-\(UUID().uuidString)", isDirectory: true)
        let legacyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dagym-provider-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        StoreMigration.containerDirectoryOverride = directory
        StoreMigration.legacyDirectoryOverride = legacyDirectory
        defer {
            StoreMigration.containerDirectoryOverride = nil
            StoreMigration.legacyDirectoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: legacyDirectory)
        }

        let preferences = Preferences(suite: makeSuite(#function))
        preferences.iCloudSyncEnabled = false
        let provider = ContainerProvider()
        let container = try #require(provider.main(cloudKitEnabled: preferences.iCloudSyncEnabled))
        #expect(provider.mainResolution == .local)

        let configuration = try #require(container.configurations.first)
        #expect(!configuration.isStoredInMemoryOnly)
        #expect(configuration.url.path.hasPrefix(directory.path))
        #expect(configuration.cloudKitContainerIdentifier == nil)
        // The intent path asks the same provider, so it gets this exact container.
        let store = try #require(provider.store(cloudKitEnabled: preferences.iCloudSyncEnabled))
        #expect(store.context === container.mainContext)
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
