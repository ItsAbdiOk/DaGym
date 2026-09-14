import SwiftUI
import UIKit

/// The app delegate exists for exactly one reason: HealthKit background delivery.
///
/// `HKObserverQuery` registration has to happen on *every* launch, including the ones iOS makes
/// on DaGym's behalf when a new sample lands while the app is closed. Those launches render no
/// scenes at all, so anything registered from a view's `.task` (where this used to live) never
/// runs: iOS never gets its completion handler back, and after a few of those it stops delivering
/// to the app entirely. `application(_:didFinishLaunchingWithOptions:)` runs on both kinds of
/// launch, which is what makes it the only correct place for this.
///
/// It deliberately does no seeding and touches no UI — `AppRootContainer` still owns all of that.
/// The only shared state is `ContainerProvider.shared` (one container per process either way) and
/// `HealthKitStore.shared` (one observer per type either way).
@MainActor
final class DaGymAppDelegate: NSObject, UIApplicationDelegate {
    /// Kept alive for the life of the process: the observer's `onChange` holds this weakly, so a
    /// service that goes out of scope would silently stop importing.
    private var healthSync: HealthSyncService?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Test hosts open their own in-memory containers and must not touch HealthKit.
        guard !LaunchFlags.isTesting else { return true }
        let preferences = Preferences()
        guard let store = ContainerProvider.shared.store(cloudKitEnabled: preferences.iCloudSyncEnabled)
        else { return true }
        let sync = HealthSyncService(workoutStore: store, preferences: preferences)
        healthSync = sync
        Task { await sync.startObservingHealthChanges() }
        return true
    }
}
