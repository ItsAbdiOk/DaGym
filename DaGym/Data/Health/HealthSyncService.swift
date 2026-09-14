import Foundation
import GymCore
import os

private let healthLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "health")

/// Owns Apple Health sync end to end: authorization, writing finished workouts to Health,
/// deleting them again when they're deleted here, pushing manual weigh-ins, and importing
/// strength sessions logged in other apps (plan.md §6.8). Every write is gated by its own
/// `Preferences` toggle, off by default — nothing reaches Health until the user turns it on in
/// `HealthSettingsView`. Bind once per launch with `bind(to:)`.
///
/// Nothing read *out* of Health is written into the CloudKit-mirrored main store (App Store
/// Guideline 5.1.3): bodyweight from Health is read live by `HealthInsightsService`, and imported
/// workouts land in the always-local Health store (`WorkoutStore+HealthImport.swift`).
@MainActor
@Observable
final class HealthSyncService {
    private let healthStore: any HealthStoring
    private let workoutStore: WorkoutStore
    private let preferences: Preferences

    private(set) var lastSyncDate: Date?
    private(set) var isAuthorizing = false
    /// Whether HealthKit's sheet has already been put to the user — the one signal it gives that
    /// tells "we never asked" apart from "we asked and a read came back empty (or denied)".
    /// Refreshed by `refreshAuthorizationStatus()`; the UI reads it to decide whether to offer
    /// "Check Health permissions" instead of silently hiding a card.
    private(set) var authorizationRequest: HealthAuthorizationRequest = .unknown

    var isAvailable: Bool { healthStore.isAvailable }

    init(
        healthStore: any HealthStoring = HealthKitStore.shared, workoutStore: WorkoutStore,
        preferences: Preferences
    ) {
        self.healthStore = healthStore
        self.workoutStore = workoutStore
        self.preferences = preferences
    }

    /// Wires `WorkoutStore.finish(session:)` and `WorkoutStore.deleteWorkout(id:)` to Health.
    /// Call once, after the store exists (see `DaGymApp.swift`). Both hooks are synchronous, so
    /// they kick off a Task — the underlying methods are also callable (and awaitable) from tests.
    func bind(to store: WorkoutStore) {
        store.onWorkoutFinished = { [weak self] workout in
            Task { await self?.syncFinishedWorkout(workout) }
        }
        store.onWorkoutDeletedFromHealth = { [weak self] healthKitID in
            Task { await self?.deleteWorkoutFromHealth(healthKitID: healthKitID) }
        }
    }

    /// Requests Health authorization. Safe to call repeatedly — HealthKit's own sheet only
    /// appears the first time (or after a type is added), and this never throws to the caller.
    func authorize() async {
        guard isAvailable else { return }
        isAuthorizing = true
        defer { isAuthorizing = false }
        do {
            try await healthStore.requestAuthorization()
        } catch {
            healthLogger.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() async {
        authorizationRequest = await healthStore.authorizationRequestStatus()
    }

    /// Whether the user has actually granted permission to write one type. Used by onboarding so
    /// a declined sheet doesn't leave the write toggles switched on.
    func canWrite(_ type: HealthShareType) async -> Bool {
        await healthStore.sharingAuthorization(for: type) == .authorized
    }

    /// Writes a finished workout to Health, unless the toggle is off, Health is unavailable, the
    /// workout has no end date yet, or it's already been synced (`healthKitID` set) — this is what
    /// makes a repeat call a no-op rather than a duplicate `HKWorkout`. Active energy is only
    /// attached when `preferences.healthEstimateCalories` is on (see `estimatedEnergyKcal`).
    func syncFinishedWorkout(_ workout: WorkoutModel) async {
        guard preferences.healthWriteWorkouts, isAvailable, workout.healthKitID == nil,
              let endedAt = workout.endedAt else { return }
        let sets = (workout.exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
        // Assisted rows log the machine's help, which is not weight lifted — the same total
        // History and the weekly recap show (`WorkoutModel.loadedVolumeKg`).
        let volumeKg = workout.loadedVolumeKg
        let workoutID = workout.id
        let energyKcal = preferences.healthEstimateCalories
            ? estimatedEnergyKcal(start: workout.startedAt, end: endedAt, bodyweightKg: workout.bodyweightKg)
            : nil
        let input = HealthWorkoutInput(
            start: workout.startedAt, end: endedAt, title: workout.title,
            routineName: workout.routineName, workoutID: workoutID.uuidString,
            setCount: sets.count, volumeKg: volumeKg, energyKcal: energyKcal,
            energyIsEstimate: energyKcal != nil
        )
        do {
            let hkID = try await healthStore.saveWorkout(input)
            // Re-fetch: the user may have deleted the workout during the HealthKit round-trip,
            // and writing to a deleted model traps.
            guard let saved = workoutStore.fetchWorkoutModel(id: workoutID) else {
                // Deleted mid-flight: don't leave our sample orphaned in Health.
                await deleteWorkoutFromHealth(healthKitID: hkID)
                return
            }
            saved.healthKitID = hkID
            workoutStore.save()
            lastSyncDate = Date()
        } catch {
            healthLogger.error("Workout save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the `HKWorkout` DaGym wrote for a workout that has since been deleted here.
    /// Unconditional on the write toggle: the sample exists because the toggle *was* on, and
    /// leaving it behind after the user turned the toggle off would be worse, not better.
    func deleteWorkoutFromHealth(healthKitID: String) async {
        guard isAvailable else { return }
        do {
            try await healthStore.deleteOwnWorkout(healthKitID: healthKitID)
        } catch {
            healthLogger.error("Workout delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pushes a manually-logged bodyweight to Health, when the toggle is on. Called by
    /// `BodyweightSheet` right after it saves the local `BodyMeasurementModel` — with **that
    /// row's own date**, not a fresh `Date()`, so the two sides carry the same instant and the
    /// day-level merge in `HealthInsightsService.mergeBodyweightSeries` folds them into one point.
    func pushBodyweight(kg: Double, date: Date) async {
        guard preferences.healthSyncBodyweight, isAvailable else { return }
        do {
            try await healthStore.saveBodyMass(kg: kg, date: date)
            lastSyncDate = Date()
        } catch {
            healthLogger.error("Bodyweight push failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Imports `HKWorkout` strength sessions logged in other apps (or the Watch) into the local
    /// Health store. `HealthKitStore.externalStrengthWorkouts` has already filtered out anything
    /// DaGym wrote itself, and `WorkoutStore.shouldSkipHealthImport` refuses anything already
    /// imported or tombstoned by a delete — so a session the user swiped away stays away.
    @discardableResult
    func pullExternalWorkouts(days: Int = 30) async -> Int {
        guard preferences.healthImportWorkouts, isAvailable else { return 0 }
        do {
            let since = Self.since(days: days)
            let external = try await healthStore.externalStrengthWorkouts(since: since)
            guard !external.isEmpty else { return 0 }
            var imported = 0
            for workout in external where workoutStore.importExternalWorkout(workout) != nil {
                imported += 1
            }
            if imported > 0 { lastSyncDate = Date() }
            return imported
        } catch {
            healthLogger.error(
                "External workout pull failed: \(error.localizedDescription, privacy: .public)"
            )
            return 0
        }
    }

    /// Registers Health's background-delivery observer for workouts, so a session logged on the
    /// Watch lands without the user opening Settings.
    ///
    /// Called from `DaGymAppDelegate.application(_:didFinishLaunchingWithOptions:)` — *not* from
    /// a view's `.task`: a HealthKit background launch renders no scenes, so a view-driven
    /// registration never happens and iOS never gets its completion handler back. Also called
    /// when a toggle is flipped, so a freshly enabled sync starts observing straight away rather
    /// than next launch; `HealthKitStore.shared` makes the repeat call a no-op.
    ///
    /// Gated on `preferences.healthAutoImportWorkouts`, which is off by default: the settings
    /// copy promises imports happen on an explicit tap, and a silent import is also what made a
    /// deleted import come back before tombstones existed.
    func startObservingHealthChanges() async {
        guard isAvailable, preferences.healthImportWorkouts,
              preferences.healthAutoImportWorkouts else { return }
        do {
            try await healthStore.observeWorkoutChanges { [weak self] in
                await self?.pullExternalWorkoutsIfAutoImportEnabled()
            }
        } catch {
            healthLogger.error(
                "Workout observer registration failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// What the background observer runs. There is no way to un-register an `HKObserverQuery`
    /// once it's live, so the toggles are re-read here, on every delivery, rather than only at
    /// registration: a lifter who turns "Import automatically" (or the import itself) off must
    /// stop getting rows in History straight away, not at the next relaunch. `preferences` is the
    /// one instance the Settings toggles mutate (`DaGymAppDelegate.preferences`), which is what
    /// makes this read see the flip.
    @discardableResult
    func pullExternalWorkoutsIfAutoImportEnabled() async -> Int {
        guard preferences.healthImportWorkouts, preferences.healthAutoImportWorkouts else { return 0 }
        return await pullExternalWorkouts()
    }

    /// A rough active-energy estimate for `syncFinishedWorkout`, using the bodyweight recorded on
    /// the workout itself when there is one, falling back to the latest known measurement and
    /// finally a generic 80kg so a first-ever sync (before any bodyweight is logged) still works.
    /// Nil when there is nothing worth writing — see `HealthUnitConversion`.
    private func estimatedEnergyKcal(start: Date, end: Date, bodyweightKg: Double?) -> Double? {
        let bodyweight = bodyweightKg ?? workoutStore.latestBodyMeasurement()?.bodyweightKg ?? 80
        let durationSeconds = Int(end.timeIntervalSince(start))
        return HealthUnitConversion.estimatedActiveEnergyKcal(
            durationSeconds: durationSeconds, bodyweightKg: bodyweight
        )
    }

    /// Calendar days back from now, matching `WorkoutStore.manualBodyweightSeries` rather than
    /// `days × 86_400` — the two used to disagree across a DST boundary, so a window that looked
    /// like "the last 90 days" covered different spans on each side of a merge.
    static func since(days: Int, calendar: Calendar = .current, now: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? .distantPast
    }
}
