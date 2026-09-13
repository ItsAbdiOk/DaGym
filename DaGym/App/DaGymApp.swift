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

/// Resolves the persistent store (falling back to an in-memory one rather
/// than crashing), seeds it, then shows `RootView` with the store injected.
struct AppRootContainer: View {
    private enum LaunchPhase {
        case loading
        case ready(WorkoutStore, HealthSyncService)
    }

    private let container: ModelContainer?
    private let preferences: Preferences
    @State private var phase = LaunchPhase.loading
    // Mirrors `preferences.hasCompletedOnboarding` in `@State` so finishing onboarding is
    // guaranteed to invalidate this view. `preferences` is a plain `let`: reading its properties
    // from `body` only reliably drives a re-render while this struct's own identity is stable,
    // and `AppRootContainer` can be re-initialized (a fresh `Preferences()`) by its parent scene,
    // which would otherwise leave onboarding stuck showing its last screen after `onComplete`.
    @State private var hasCompletedOnboarding: Bool
    // Set only by `onComplete` below — distinguishes "just finished onboarding this launch" from
    // "onboarding was already done", so `RootView` only pays its post-onboarding startup delay
    // (see `RootView.justCompletedOnboarding`) when it's actually replacing `OnboardingFlow`.
    @State private var justCompletedOnboarding = false

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
        container = Self.resolveContainer(cloudKitEnabled: preferences.iCloudSyncEnabled)
    }

    var body: some View {
        Group {
            if LaunchFlags.isUnitTestHost {
                // Unit tests build their own in-memory containers; the host app must do nothing
                // (no seeding, notifications, HealthKit, widgets) so the runner connects instantly.
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
                .task { await seed(context: container.mainContext) }
        case .ready(let store, let healthSync):
            Group {
                if hasCompletedOnboarding {
                    RootView(justCompletedOnboarding: justCompletedOnboarding)
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
                        justCompletedOnboarding = true
                        preferences.hasCompletedOnboarding = true
                    })
                }
            }
            .environment(store)
            .environment(preferences)
            .environment(healthSync)
            .modelContainer(container)
            .task { healthSync.bind(to: store) }
        }
    }

    private func seed(context: ModelContext) async {
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        EquipmentSeeder.seedIfNeeded(store: store)
        let healthSync = HealthSyncService(workoutStore: store, preferences: preferences)
        TrainingNotificationScheduler().bind(store: store, preferences: preferences)
        phase = .ready(store, healthSync)
    }

    /// Tries the persistent store first (with CloudKit sync if `cloudKitEnabled`), retries
    /// without CloudKit if that specifically fails (no iCloud account, simulator without
    /// sign-in, missing entitlement on an ad-hoc build), then falls back to an in-memory store so
    /// no disk/CloudKit/migration failure ever crashes the app. Under `-dgUITest`, always uses a
    /// fresh in-memory store so every test run starts seeded and empty, with no leftover state
    /// from a previous run.
    private static func resolveContainer(cloudKitEnabled: Bool) -> ModelContainer? {
        if LaunchFlags.isTesting {
            return try? ModelContainer.dagym(inMemory: true)
        }
        if let container = try? ModelContainer.dagym(cloudKitEnabled: cloudKitEnabled) {
            return container
        }
        if cloudKitEnabled {
            appLogger.error("CloudKit-backed store failed to load; retrying with sync disabled.")
            if let container = try? ModelContainer.dagym(cloudKitEnabled: false) {
                return container
            }
        }
        appLogger.error("Persistent store failed to load; falling back to an in-memory store.")
        if let container = try? ModelContainer.dagym(inMemory: true) {
            return container
        }
        appLogger.fault("In-memory store also failed to load; DaGym has no working store this launch.")
        return nil
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
