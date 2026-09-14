import Foundation
import SwiftData
import os

private let containerLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "container")

/// Resolves the main and photo `ModelContainer`s once per process and hands the same instances
/// to every caller — the app shell (`AppRootContainer`), App Intents that run inside the app
/// process (`IntentStoreAccess`), and anything else that would otherwise open a second
/// container (and a second CloudKit mirror) on the same store files.
///
/// Resolution order for the main store: the persistent store with CloudKit sync if
/// `cloudKitEnabled`, then without CloudKit if that specifically fails (no iCloud account,
/// simulator without sign-in, missing entitlement on an ad-hoc build), then an in-memory store
/// so no disk/CloudKit/migration failure ever crashes the app. `inMemory` (test processes) skips
/// straight to a fresh in-memory store so every run starts empty.
@MainActor
final class ContainerProvider {
    /// What `main(cloudKitEnabled:)` actually got, for the caller to log or display.
    enum Resolution: Equatable {
        case cloudKit
        case local
        /// A deliberate in-memory store: a test or preview process. Nothing is expected to last.
        case inMemory
        /// The on-disk store could **not** be opened and an in-memory one was substituted. The
        /// app must say so rather than looking like a fresh install: everything logged into
        /// this store is gone the moment the process exits.
        case inMemoryFallback
        case unavailable

        /// Whether a real, durable store was opened. `false` means the app must not let the
        /// user train into it.
        var isDurable: Bool { self == .cloudKit || self == .local }
    }

    static let shared = ContainerProvider(inMemory: LaunchFlags.isTesting)

    private let inMemory: Bool
    private var mainContainer: ModelContainer?
    private var photoContainer: ModelContainer?
    private var photosResolved = false
    private var healthContainer: ModelContainer?
    private var healthResolved = false
    private var sharedStore: WorkoutStore?
    private(set) var mainResolution: Resolution?

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    /// The main container, resolved on first call and cached for the life of the process.
    /// `cloudKitEnabled` (`Preferences.iCloudSyncEnabled`) is only consulted on that first call;
    /// the store's CloudKit configuration is fixed once it is open, so a toggle takes effect on
    /// the next launch.
    func main(cloudKitEnabled: Bool) -> ModelContainer? {
        if mainResolution != nil { return mainContainer }
        let (container, resolution) = Self.resolveMain(inMemory: inMemory, cloudKitEnabled: cloudKitEnabled)
        mainContainer = container
        mainResolution = resolution
        return container
    }

    /// The always-local progress-photo container, or `nil` if it failed to open (photo features
    /// then read as empty and refuse writes — see `WorkoutStore.photoContext`).
    func photos() -> ModelContainer? {
        if photosResolved { return photoContainer }
        photosResolved = true
        do {
            photoContainer = try ModelContainer.dagymPhotos(inMemory: inMemory)
        } catch {
            let message = error.localizedDescription
            containerLogger.error("Photo store failed to load: \(message, privacy: .public)")
        }
        return photoContainer
    }

    /// The always-local store for HealthKit-derived rows (imported external workouts and their
    /// delete tombstones), or `nil` if it failed to open — Health import then reads as empty and
    /// refuses writes rather than falling back to the CloudKit-mirrored main store, which
    /// Guideline 5.1.3 forbids. See `WorkoutStore.healthContext`.
    func healthImports() -> ModelContainer? {
        if healthResolved { return healthContainer }
        healthResolved = true
        do {
            healthContainer = try ModelContainer.dagymHealth(inMemory: inMemory)
        } catch {
            let message = error.localizedDescription
            containerLogger.error("Health store failed to load: \(message, privacy: .public)")
        }
        return healthContainer
    }

    /// One `WorkoutStore` over the main container's `mainContext`, shared by the app shell and
    /// the intents so a bodyweight logged through Siri is written by the context the open app
    /// is reading from.
    func store(cloudKitEnabled: Bool) -> WorkoutStore? {
        if let sharedStore { return sharedStore }
        guard let container = main(cloudKitEnabled: cloudKitEnabled) else { return nil }
        let store = WorkoutStore(
            context: container.mainContext, photoContext: photos().map(ModelContext.init),
            healthContext: healthImports().map(ModelContext.init)
        )
        sharedStore = store
        return store
    }

    private static func resolveMain(
        inMemory: Bool, cloudKitEnabled: Bool
    ) -> (ModelContainer?, Resolution) {
        if !inMemory {
            if cloudKitEnabled, let container = try? ModelContainer.dagym(cloudKitEnabled: true) {
                return (container, .cloudKit)
            }
            if cloudKitEnabled {
                containerLogger.error("CloudKit-backed store failed to load; retrying with sync disabled.")
            }
            if let container = try? ModelContainer.dagym(cloudKitEnabled: false) {
                return (container, .local)
            }
            containerLogger.fault(
                "Persistent store failed to load; substituting a throwaway in-memory store."
            )
            if let container = try? ModelContainer.dagym(inMemory: true) {
                return (container, .inMemoryFallback)
            }
            containerLogger.fault("In-memory store also failed to load; DaGym has no store this launch.")
            return (nil, .unavailable)
        }
        if let container = try? ModelContainer.dagym(inMemory: true) {
            return (container, .inMemory)
        }
        containerLogger.fault("In-memory store also failed to load; DaGym has no working store this launch.")
        return (nil, .unavailable)
    }
}
