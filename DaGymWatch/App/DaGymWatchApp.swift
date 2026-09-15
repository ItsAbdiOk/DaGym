import HealthKit
import SwiftData
import SwiftUI
import WatchKit

@main
struct DaGymWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @State private var root = WatchRoot()

    var body: some Scene {
        WindowGroup {
            Group {
                if let store = root.store {
                    WatchContentView()
                        .environment(store)
                        .environment(store.preferences)
                } else {
                    Text("DaGym couldn't open its data.")
                        .font(WatchFont.body)
                        .multilineTextAlignment(.center)
                }
            }
            .task { root.open() }
        }
    }
}

/// Opens the store once. The watch has its own copy of the SwiftData store, mirrored through
/// the same CloudKit container as the phone (`ModelContainer.dagym`), so exercises, routines,
/// the schedule and history arrive by sync — the watch never seeds. With no iCloud account the
/// store still opens, local-only, and syncs once one appears.
@MainActor
@Observable
final class WatchRoot {
    private(set) var store: WatchStore?
    /// Kept alive here: a `ModelContext` only weakly references its container, and a fetch on
    /// a context whose container has been released traps inside SwiftData.
    private var container: ModelContainer?

    func open() {
        guard store == nil, !WatchLaunchFlags.isTestHost else { return }
        let container = Self.makeContainer()
        guard let container else { return }
        self.container = container
        let workoutStore = WorkoutStore(context: container.mainContext, photoContext: nil)
        #if DEBUG
        if WatchLaunchFlags.isSample { WatchSampleSeeder.seed(store: workoutStore) }
        #endif
        let watchStore = WatchStore(store: workoutStore)
        watchStore.refreshHome()
        store = watchStore
        WatchWorkoutRecovery.shared.attach(to: watchStore)
        WatchSnapshotWriter.refresh(store: workoutStore, rest: nil)
    }

    private static func makeContainer() -> ModelContainer? {
        if WatchLaunchFlags.isSample { return try? ModelContainer.dagym(inMemory: true) }
        if let cloud = try? ModelContainer.dagym(cloudKitEnabled: true) { return cloud }
        return try? ModelContainer.dagym(cloudKitEnabled: false)
    }
}

/// watchOS relaunches DaGym after it was killed mid-workout (memory pressure, a force-quit)
/// so it can re-attach to the `HKWorkoutSession` still running; ignoring the call leaves that
/// session orphaned and the next `HKWorkoutSession(...)` failing as "already active".
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        HKHealthStore().recoverActiveWorkoutSession { session, _ in
            guard let session else { return }
            Task { @MainActor in WatchWorkoutRecovery.shared.offer(session) }
        }
    }
}

/// Meets the recovered session and the opened store in either order: the delegate may be told
/// before or after `WatchRoot.open` has run.
@MainActor
final class WatchWorkoutRecovery {
    static let shared = WatchWorkoutRecovery()

    private var pending: HKWorkoutSession?
    private weak var store: WatchStore?

    func offer(_ session: HKWorkoutSession) {
        pending = session
        deliver()
    }

    func attach(to store: WatchStore) {
        self.store = store
        deliver()
    }

    private func deliver() {
        guard let store, let session = pending else { return }
        pending = nil
        store.adoptRecoveredRuntime(session)
    }
}
