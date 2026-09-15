import SwiftUI
import UIKit
import UserNotifications

/// The app delegate runs the two things that must happen on *every* launch, before any scene
/// exists: HealthKit background delivery, and clearing rest Live Activities left behind by a
/// previous process.
///
/// `HKObserverQuery` registration has to happen on *every* launch, including the ones iOS makes
/// on DaGym's behalf when a new sample lands while the app is closed. Those launches render no
/// scenes at all, so anything registered from a view's `.task` (where this used to live) never
/// runs: iOS never gets its completion handler back, and after a few of those it stops delivering
/// to the app entirely. `application(_:didFinishLaunchingWithOptions:)` runs on both kinds of
/// launch, which is what makes it the only correct place for this.
///
/// The Live Activity cleanup is here for a related reason: it used to run only inside
/// `RestActivityController.shared`'s initialiser, and `shared` is first touched from the workout
/// screen — so a jetsam mid-rest left a dead banner (with dead buttons) on the Lock Screen until
/// the lifter opened a workout again. `didFinishLaunching` is the earliest point we know the
/// process that owned the banner is gone.
///
/// It deliberately does no seeding and touches no UI — `AppRootContainer` still owns all of that.
/// The only shared state is `ContainerProvider.shared` (one container per process either way) and
/// `HealthKitStore.shared` (one observer per type either way).
@MainActor
final class DaGymAppDelegate: NSObject, UIApplicationDelegate {
    /// The process's one `Preferences`. `AppRootContainer` is handed this same instance (see
    /// `DaGymApp.body`) and puts it in the SwiftUI environment, so the Settings toggles mutate
    /// exactly what the Health observer below reads on every delivery. A private `Preferences()`
    /// here used to be a snapshot frozen at launch: turning "Import automatically" off in Settings
    /// changed nothing about the background observer until the next relaunch.
    let preferences = Preferences()
    /// Kept alive for the life of the process: the observer's `onChange` holds this weakly, so a
    /// service that goes out of scope would silently stop importing.
    private var healthSync: HealthSyncService?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Test hosts open their own in-memory containers and must not touch HealthKit; a
        // `-dgInitCloudKitSchema` launch must not open the real store at all.
        guard !LaunchFlags.isTesting, !LaunchFlags.initializesCloudKitSchema else { return true }
        // One delegate for the life of the process, set here rather than only inside
        // `NotificationPermission.requestIfNeeded` — a user who has already granted permission
        // never calls that, and would get a banner over their own workout screen.
        UNUserNotificationCenter.current().delegate = RestNotificationDelegate.shared
        RestActivityController.endStaleActivitiesAtLaunch()
        guard let store = ContainerProvider.shared.store(cloudKitEnabled: preferences.iCloudSyncEnabled)
        else { return true }
        let sync = HealthSyncService(workoutStore: store, preferences: preferences)
        healthSync = sync
        Task { await sync.startObservingHealthChanges() }
        return true
    }
}
