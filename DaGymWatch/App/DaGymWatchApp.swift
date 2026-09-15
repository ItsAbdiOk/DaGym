import SwiftData
import SwiftUI

@main
struct DaGymWatchApp: App {
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
        WatchSnapshotWriter.refresh(store: workoutStore, rest: nil)
    }

    private static func makeContainer() -> ModelContainer? {
        if WatchLaunchFlags.isSample { return try? ModelContainer.dagym(inMemory: true) }
        if let cloud = try? ModelContainer.dagym(cloudKitEnabled: true) { return cloud }
        return try? ModelContainer.dagym(cloudKitEnabled: false)
    }
}
