import SwiftData
import SwiftUI
import UIKit
import os

private let appLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "app")
private let launchSignposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

@main
struct DaGymApp: App {
    // HealthKit background delivery only — see `DaGymAppDelegate`. A HealthKit background launch
    // renders no scenes, so observer registration cannot live in a view's `.task`.
    @UIApplicationDelegateAdaptor(DaGymAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            if LaunchFlags.initializesCloudKitSchema {
                // Never reaches `AppRootContainer`, so the real store is never opened.
                schemaInitView
            } else if LaunchFlags.isScreenshotting {
                ScreenshotRootView(screen: ScreenshotScreen.fromLaunchArguments)
            } else if let route = DebugRoute.fromLaunchArguments {
                DebugRootView(route: route)
            } else {
                AppRootContainer(preferences: appDelegate.preferences, healthSync: appDelegate.healthSync)
            }
        }
    }

    @ViewBuilder
    private var schemaInitView: some View {
        #if DEBUG
        SchemaInitStatusView()
        #else
        EmptyView()
        #endif
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
    /// The app delegate's `HealthSyncService` (nil in test hosts and schema-init launches),
    /// reused rather than re-created so the background observer and the finish hooks share one
    /// `lastSyncDate`/authorization state — two instances over the same store used to diverge.
    private let healthSync: HealthSyncService?
    @State private var phase = LaunchPhase.loading
    // Mirrors `preferences.hasCompletedOnboarding` in `@State` so finishing onboarding is
    // guaranteed to invalidate this view. `preferences` is a plain `let`: reading its properties
    // from `body` only reliably drives a re-render while this struct's own identity is stable,
    // and `AppRootContainer` can be re-initialized by its parent scene, which would otherwise
    // leave onboarding stuck showing its last screen after `onComplete`.
    // The container itself is not stored here for the same reason: `ContainerProvider.shared`
    // resolves it once, so a re-init never opens a second container on the same store files.
    @State private var hasCompletedOnboarding: Bool
    /// Which coach model the app talks to (on-device Foundation Models or the rules), decided
    /// once from preferences and device state; Settings re-checks it on toggle.
    @State private var coachServices: CoachServices

    /// `preferences` is the app delegate's instance — the one process-wide `Preferences`, so the
    /// HealthKit background observer and the scenes read and write the same object.
    init(preferences: Preferences, healthSync: HealthSyncService? = nil) {
        if LaunchFlags.isUITesting {
            UIView.setAnimationsEnabled(false)
            // `-dgUITest` alone should land existing smoke tests straight on the tab bar;
            // `-dgUITest -dgOnboarding` resets onboarding so `testOnboardingCompletes` always
            // starts fresh, regardless of what a previous simulator run left in UserDefaults.
            preferences.hasCompletedOnboarding = !LaunchFlags.forcesOnboarding
        }
        self.preferences = preferences
        self.healthSync = healthSync
        _hasCompletedOnboarding = State(initialValue: preferences.hasCompletedOnboarding)
        _coachServices = State(initialValue: CoachServices.make(preferences: preferences))
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
            } else if let container, storeIsUsable {
                launchContent(container: container)
            } else {
                storageUnavailable
            }
        }
    }

    /// False when the store that opened is not durable — either nothing opened at all, or the
    /// on-disk store failed and `ContainerProvider` substituted a throwaway in-memory one.
    ///
    /// That substitution used to be invisible: the app seeded the empty in-memory store and
    /// looked exactly like a fresh install, so a lifter could train into it for a week and lose
    /// every session the moment the process was killed. A `-dgUITest` run is the one case where
    /// an in-memory store is the point, so it is allowed through.
    private var storeIsUsable: Bool {
        guard !LaunchFlags.isTesting else { return true }
        return ContainerProvider.shared.mainResolution?.isDurable ?? false
    }

    private var storageUnavailable: some View {
        ZStack {
            AmbientWash()
            EmptyState(
                symbol: "exclamationmark.triangle",
                title: "Your Data Couldn't Be Opened",
                message: """
                    DaGym found its database but couldn't open it, so it hasn't started. \
                    Your training history is still on this device — nothing has been deleted. \
                    Try relaunching; if that doesn't help, restart your iPhone before \
                    reinstalling, since reinstalling would remove the local copy.
                    """
            )
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
            .environment(coachServices)
            .modelContainer(container)
            .preferredColorScheme(preferences.appearance.colorScheme)
        }
    }

    private func seed() async {
        let provider = ContainerProvider.shared
        guard let store = provider.store(cloudKitEnabled: preferences.iCloudSyncEnabled) else { return }
        let interval = launchSignposter.beginInterval("coldLaunchSeed")
        // A store already at the bundled seed version returns from each seeder after a count or
        // a flag read; the 1.4 MB JSON is only decoded (off the main actor) on a version bump or
        // a fresh install. The one fold pass for everything is `dedupeSeededRows()` below.
        await ExerciseSeeder.seedIfNeededAsync(context: store.context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        EquipmentSeeder.seedIfNeeded(store: store, unit: preferences.weightUnit)
        store.dedupeSeededRows()
        // Warm-ups round onto the lifter's own rack, not a bare increment. `WorkoutSession`
        // is store-free, so this is where the two are introduced — before any session exists.
        WorkoutSession.defaultWarmupGrid = { [weak store] exercise in
            guard let store else { return .step(max(exercise.incrementKg, 0.5)) }
            return store.loadGrid(for: exercise, equipment: store.activeEquipment())
        }
        purgeHealthDerivedRowsOnce(store: store)
        store.backfillWorkoutTotalsIfNeeded()
        // A second iCloud device imports the first one's seeded rows after launch; fold those
        // as they land. Kept in `phase` so the observer lives as long as the store does.
        let deduper = store.startRemoteChangeDedupe()
        let sync = self.healthSync ?? HealthSyncService(workoutStore: store, preferences: preferences)
        let healthInsights = HealthInsightsService(workoutStore: store, preferences: preferences)
        // Both finish hooks are wired *before* the stale-workout purge below: it auto-finishes
        // forgotten sessions through `finish(session:)`, and a session finished before the
        // hooks existed never reached Apple Health or rescheduled the streak/recap reminders.
        sync.bind(to: store)
        TrainingNotificationScheduler().bind(store: store, preferences: preferences)
        // Workouts left open for more than a day are cleared out before `RootView` offers to
        // resume anything newer. Nothing logged is destroyed: one with completed sets in it is
        // auto-finished at its own last set, and only an empty shell is deleted — see
        // `purgeUnfinished(olderThan:)`.
        store.purgeUnfinished(olderThan: Date().addingTimeInterval(-24 * 60 * 60))
        // Background delivery is registered in `DaGymAppDelegate` instead — a HealthKit
        // background launch renders no scenes, so a `.task` would never run on exactly the
        // launches that need it.
        launchSignposter.endInterval("coldLaunchSeed", interval)
        phase = .ready(store, sync, healthInsights, deduper)
    }

    /// One-time repair: the first Apple Health build wrote HealthKit-derived rows into the
    /// CloudKit-mirrored main store. Move/clear them — App Store Guideline 5.1.3. Gated on the
    /// seed-state row like the other seeders: it used to run its two predicate fetches on every
    /// launch, forever, for a build almost nobody still has data from.
    private func purgeHealthDerivedRowsOnce(store: WorkoutStore) {
        let state = SeedState.row(in: store.context)
        guard !state.healthRowsPurged else { return }
        store.purgeHealthDerivedRowsFromMainStore()
        state.healthRowsPurged = true
        state.updatedAt = Date()
        store.save()
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
                    .environment(CoachServices.make(preferences: preferences))
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
