#if DEBUG
import CloudKit
import CoreData
import Foundation
import SwiftData
import SwiftUI

/// Debug-only: pushes every synced record type and field into the CloudKit Development
/// schema in one shot, driven by `scripts/cloudkit-schema.sh` through the
/// `-dgInitCloudKitSchema` launch flag (`LaunchFlags.initializesCloudKitSchema`).
///
/// SwiftData only creates a CloudKit record type or field the first time a row carrying it
/// exports, which is what the old `CloudKitSchemaProbe` worked around by inserting fake rows
/// and waiting a minute. `NSPersistentCloudKitContainer.initializeCloudKitSchema` does the same
/// job directly from the model, with no rows at all: the SwiftData schema is converted to the
/// Core Data model SwiftData itself mirrors through, loaded into a throwaway store in the temp
/// directory, and the container asks CloudKit to create every type and field. The real store
/// is never opened. Only `DaGymSchema.mainModels` is initialised — the photo and health stores
/// are local-only by design (App Store Guideline 5.1.3 for health) and must never gain CloudKit
/// record types.
///
/// The outcome is written to `Documents/schema-init.json` so the script can poll for it.
enum CloudKitSchemaInitializer {
    /// What the script reads back. `error` is nil on success.
    struct Result: Codable, Equatable {
        var ok: Bool
        var error: String?
        var recordTypes: Int
    }

    static let containerID = "iCloud.dev.abdirahmanmohamed.dagym"
    static let markerFileName = "schema-init.json"

    /// `Documents/schema-init.json` — the app's Documents directory is the one place both
    /// `simctl get_app_container … data` and `devicectl device copy from` can read a file from.
    static var markerURL: URL {
        URL.documentsDirectory.appending(path: markerFileName)
    }

    /// CloudKit's own account check. Not `ubiquityIdentityToken`: that is iCloud *Drive*'s
    /// identity and is nil whenever Drive is off — which it always is on a simulator — while
    /// the private database is available as soon as an Apple ID is signed in.
    static func cloudKitAccountAvailable(containerID: String) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var status = CKAccountStatus.couldNotDetermine
        CKContainer(identifier: containerID).accountStatus { result, _ in
            status = result
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
        return status == .available
    }

    /// Runs the initialisation synchronously (it blocks for the CloudKit round trips, so call
    /// it off the main actor) and returns the result without writing it. `hasAccount` is
    /// injectable so the "no iCloud account" refusal can be tested without a device.
    static func run(
        models: [any PersistentModel.Type] = DaGymSchema.mainModels,
        containerID: String = containerID,
        hasAccount: () -> Bool = { cloudKitAccountAvailable(containerID: containerID) }
    ) -> Result {
        guard hasAccount() else { return failure("no iCloud account") }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else {
            return failure("SwiftData schema could not be converted to a Core Data model")
        }
        let container = NSPersistentCloudKitContainer(name: "DaGymSchemaInit", managedObjectModel: model)
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "dagym-schema-init-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        // `initializeCloudKitSchema` refuses a store without history tracking.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            return failure("store failed to load: \(loadError.localizedDescription)")
        }
        defer { removeThrowawayStore(container: container, at: storeURL) }
        do {
            try container.initializeCloudKitSchema(options: [])
        } catch {
            return failure("initializeCloudKitSchema: \(error.localizedDescription)")
        }
        return Result(ok: true, error: nil, recordTypes: model.entities.count)
    }

    /// Runs `run()` and writes the outcome to `url` (`markerURL` by default). A failure to write
    /// is folded into the returned result so the caller can still show it.
    static func runAndWriteMarker(to url: URL = markerURL) -> Result {
        var result = run()
        do {
            try write(result, to: url)
        } catch {
            result = failure("marker write failed: \(error.localizedDescription)")
        }
        return result
    }

    private static func failure(_ message: String) -> Result {
        Result(ok: false, error: message, recordTypes: 0)
    }

    static func write(_ result: Result, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(result).write(to: url, options: .atomic)
    }

    private static func removeThrowawayStore(container: NSPersistentCloudKitContainer, at url: URL) {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        try? coordinator.destroyPersistentStore(at: url, type: .sqlite)
    }
}

/// The whole UI of a `-dgInitCloudKitSchema` launch: kicks off the initialiser off the main
/// actor and shows its outcome. The script does not read this view — it polls the marker file —
/// so it only needs to tell a human at the device what happened.
struct SchemaInitStatusView: View {
    @State private var result: CloudKitSchemaInitializer.Result?

    var body: some View {
        VStack(spacing: 16) {
            if let result {
                Image(systemName: result.ok ? "checkmark.icloud" : "xmark.icloud")
                    .font(.system(size: 48))
                    .foregroundStyle(result.ok ? Color.green : Color.red)
                Text(result.ok ? "Schema initialised — you can close this" : "Schema initialisation failed")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(result.ok
                    ? "\(result.recordTypes) record types pushed to the Development schema."
                    : result.error ?? "Unknown error")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                Text("Initialising CloudKit schema…")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            result = await Task.detached(priority: .userInitiated) {
                CloudKitSchemaInitializer.runAndWriteMarker()
            }.value
        }
    }
}
#endif
