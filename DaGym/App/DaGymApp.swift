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

    init() {
        if LaunchFlags.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        let preferences = Preferences()
        self.preferences = preferences
        container = Self.resolveContainer(cloudKitEnabled: preferences.iCloudSyncEnabled)
    }

    var body: some View {
        Group {
            if let container {
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
            RootView()
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
