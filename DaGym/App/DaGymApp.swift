import SwiftData
import SwiftUI
import UIKit
import os

private let appLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "app")

@main
struct DaGymApp: App {
    var body: some Scene {
        WindowGroup {
            if let route = DebugRoute.fromLaunchArguments {
                DebugRootView(route: route)
            } else {
                AppRootContainer()
            }
        }
    }
}

/// Resolves the persistent store through `ContainerProvider` (once per process, falling back
/// to an in-memory one rather than crashing), seeds it, then shows `RootView` with the store
/// injected.
struct AppRootContainer: View {
    private enum LaunchPhase {
        case loading
        case ready(WorkoutStore, HealthSyncService, HealthInsightsService, RemoteChangeDeduper)
    }

    private let preferences: Preferences
    @State private var phase = LaunchPhase.loading
    // Mirrors `preferences.hasCompletedOnboarding` in `@State` so finishing onboarding is
    // guaranteed to invalidate this view. `preferences` is a plain `let`: reading its properties
    // from `body` only reliably drives a re-render while this struct's own identity is stable,
    // and `AppRootContainer` can be re-initialized (a fresh `Preferences()`) by its parent scene,
    // which would otherwise leave onboarding stuck showing its last screen after `onComplete`.
    // The container itself is not stored here for the same reason: `ContainerProvider.shared`
    // resolves it once, so a re-init never opens a second container on the same store files.
    @State private var hasCompletedOnboarding: Bool

    init() {
        if LaunchFlags.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        let preferences = Preferences()
        if LaunchFlags.isUITesting {
            // `-dgUITest` alone should land existing smoke tests straight on the tab bar;
            // `-dgUITest -dgOnboarding` resets onboarding so `testOnboardingCompletes` always
            // starts fresh, regardless of what a previous simulator run left in UserDefaults.
            preferences.hasCompletedOnboarding = !LaunchFlags.forcesOnboarding
        }
        self.preferences = preferences
        _hasCompletedOnboarding = State(initialValue: preferences.hasCompletedOnboarding)
    }

    private var container: ModelContainer? {
        ContainerProvider.shared.main(cloudKitEnabled: preferences.iCloudSyncEnabled)
    }

    var body: some View {
        Group {
            if LaunchFlags.isUnitTestHost, !LaunchFlags.isUITesting {
                // Unit tests build their own in-memory containers; the host app must do nothing
                // (no seeding, notifications, HealthKit, widgets) so the runner connects instantly.
                // A `-dgUITest` launch always wins, though: it must land on the seeded in-memory
                // store even if the XCTest environment `isUnitTestHost` sniffs for leaks in.
                AmbientWash()
            } else if let container {
                launchContent(container: container)
            } else {
                ZStack {
                    AmbientWash()
                    EmptyState(
                        symbol: "exclamationmark.triangle",
                        title: "Storage Unavailable",
                        message: "DaGym couldn't open its database. Try relaunching the app."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func launchContent(container: ModelContainer) -> some View {
        switch phase {
        case .loading:
            AmbientWash()
                .modelContainer(container)
                .task { await seed() }
        case .ready(let store, let healthSync, let healthInsights, _):
            Group {
                if hasCompletedOnboarding {
                    RootView()
                } else {
                    OnboardingFlow(onComplete: {
                        // Flip the `@State` gate first: it's what this view's `body` actually
                        // switches on, so setting it first means the very next render already
                        // shows `RootView`. `preferences` is `@Observable` and read elsewhere
                        // (e.g. re-launch), so mutating it too is still needed for persistence —
                        // but mutating it *before* the `@State` flip made its own change
                        // notification force an extra synchronous re-render in between (still
                        // showing `OnboardingFlow`, since the `@State` flip hadn't happened yet),
                        // which raced with `RootView`'s first layout and either left it
                        // un-hit-testable or crashed SwiftData's fetch mid-transition. Ordering it
                        // second makes that extra render harmless: it just redraws `RootView`.
                        hasCompletedOnboarding = true
                        preferences.hasCompletedOnboarding = true
                    })
                }
            }
            .environment(store)
            .environment(preferences)
            .environment(healthSync)
            .environment(healthInsights)
            .modelContainer(container)
            .preferredColorScheme(preferences.appearance.colorScheme)
            .task { healthSync.bind(to: store) }
        }
    }

    private func seed() async {
        let provider = ContainerProvider.shared
        guard let store = provider.store(cloudKitEnabled: preferences.iCloudSyncEnabled) else { return }
        ExerciseSeeder.seedIfNeeded(context: store.context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        EquipmentSeeder.seedIfNeeded(store: store)
        store.dedupeSeededRows()
        // A second iCloud device imports the first one's seeded rows after launch; fold those
        // as they land. Kept in `phase` so the observer lives as long as the store does.
        let deduper = store.startRemoteChangeDedupe()
        // Half-finished workouts older than a day are abandoned, not resumable; `RootView`
        // offers to resume anything newer.
        store.purgeUnfinished(olderThan: Date().addingTimeInterval(-24 * 60 * 60))
        let healthSync = HealthSyncService(workoutStore: store, preferences: preferences)
        let healthInsights = HealthInsightsService(workoutStore: store, preferences: preferences)
        TrainingNotificationScheduler().bind(store: store, preferences: preferences)
        // Background delivery (plan.md §6.8): keeps bodyweight and imported workouts current
        // without the user opening Settings. No-ops until Health has been authorized at least
        // once, so this is safe to call unconditionally on every launch.
        Task { await healthSync.startObservingHealthChanges() }
        phase = .ready(store, healthSync, healthInsights, deduper)
    }
}

/// The `-dgScreen` debug entry point: a throwaway in-memory store so every
/// screen (including store-backed ones) has an environment to read from.
struct DebugRootView: View {
    let route: DebugRoute

    private let preferences = Preferences()
    @State private var container: ModelContainer?
    @State private var store: WorkoutStore?

    var body: some View {
        Group {
            if let container, let store {
                DebugScreenView(route: route)
                    .environment(store)
                    .environment(preferences)
                    .modelContainer(container)
            } else {
                AmbientWash()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let resolved = try? ModelContainer.dagym(inMemory: true) else {
            appLogger.error("Debug in-memory store failed to load.")
            return
        }
        ExerciseSeeder.seedIfNeeded(context: resolved.mainContext)
        let newStore = WorkoutStore(context: resolved.mainContext)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: newStore)
        container = resolved
        store = newStore
    }
}
