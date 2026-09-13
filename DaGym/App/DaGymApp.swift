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
        case ready(WorkoutStore)
    }

    private let container: ModelContainer?
    @State private var phase = LaunchPhase.loading

    init() {
        if LaunchFlags.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        container = Self.resolveContainer()
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
        case .ready(let store):
            RootView()
                .environment(store)
                .modelContainer(container)
        }
    }

    private func seed(context: ModelContext) async {
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        phase = .ready(store)
    }

    /// Tries the persistent store first; falls back to an in-memory one so a
    /// disk or migration failure never crashes the app.
    private static func resolveContainer() -> ModelContainer? {
        if let container = try? ModelContainer.dagym() {
            return container
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

    @State private var container: ModelContainer?
    @State private var store: WorkoutStore?

    var body: some View {
        Group {
            if let container, let store {
                DebugScreenView(route: route)
                    .environment(store)
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
