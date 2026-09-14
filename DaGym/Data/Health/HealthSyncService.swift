import Foundation
import GymCore
import os

private let healthLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "health")

/// Owns Apple Health sync end to end: authorization, writing finished workouts, and two-way
/// bodyweight sync (plan.md §6.8). Every write is gated by its own `Preferences` toggle, off by
/// default — nothing reaches Health until the user turns it on in `HealthSettingsView`. Bind once
/// per launch with `bind(to:)` so `WorkoutStore.finish(session:)` syncs automatically.
@MainActor
@Observable
final class HealthSyncService {
    private let healthStore: any HealthStoring
    private let workoutStore: WorkoutStore
    private let preferences: Preferences

    private(set) var lastSyncDate: Date?
    private(set) var isAuthorizing = false

    var isAvailable: Bool { healthStore.isAvailable }

    init(
        healthStore: any HealthStoring = HealthKitStore(), workoutStore: WorkoutStore,
        preferences: Preferences
    ) {
        self.healthStore = healthStore
        self.workoutStore = workoutStore
        self.preferences = preferences
    }

    /// Wires `WorkoutStore.finish(session:)` to sync automatically. Call once, after the store
    /// exists (see `DaGymApp.swift`). The hook itself is synchronous, so it just kicks off a Task —
    /// `syncFinishedWorkout` is also callable directly (and awaitable) from tests.
    func bind(to store: WorkoutStore) {
        store.onWorkoutFinished = { [weak self] workout in
            Task { await self?.syncFinishedWorkout(workout) }
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
    }

    /// Writes a finished workout to Health, unless the toggle is off, Health is unavailable, the
    /// workout has no end date yet, or it's already been synced (`healthKitID` set) — this is what
    /// makes a repeat call a no-op rather than a duplicate `HKWorkout`. Active energy is only
    /// attached when `preferences.healthEstimateCalories` is on (see `estimatedEnergyKcal` and
    /// the comment on `HealthKitStore.saveWorkout`) — this app has no heart-rate sensor of its
    /// own, so a "real" energy figure would have to come from a future Watch session (P5), which
    /// isn't wired up yet.
    func syncFinishedWorkout(_ workout: WorkoutModel) async {
        guard preferences.healthWriteWorkouts, isAvailable, workout.healthKitID == nil,
              let endedAt = workout.endedAt else { return }
        let sets = (workout.exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
        let volumeKg = sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
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
            guard let saved = workoutStore.fetchWorkoutModel(id: workoutID) else { return }
            saved.healthKitID = hkID
            workoutStore.save()
            lastSyncDate = Date()
        } catch {
            healthLogger.error("Workout save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pulls the latest Health bodyweight and logs it as a `source: "health"` measurement, but only
    /// if it's newer than what's already stored — Health is the source of truth when this toggle is
    /// on, but a same-or-earlier reading never overwrites a fresher manual entry.
    func pullBodyweight() async {
        guard preferences.healthSyncBodyweight, isAvailable else { return }
        do {
            guard let latest = try await healthStore.latestBodyMass() else { return }
            if let ours = workoutStore.latestBodyMeasurement(), latest.date <= ours.date { return }
            workoutStore.logBodyweight(kg: latest.kg, date: latest.date, source: "health")
            lastSyncDate = Date()
        } catch {
            healthLogger.error("Bodyweight pull failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pushes a manually-logged bodyweight to Health, when the toggle is on. Called by
    /// `BodyweightSheet` right after it saves the local `BodyMeasurementModel`.
    func pushBodyweight(kg: Double, date: Date = Date()) async {
        guard preferences.healthSyncBodyweight, isAvailable else { return }
        do {
            try await healthStore.saveBodyMass(kg: kg, date: date)
            lastSyncDate = Date()
        } catch {
            healthLogger.error("Bodyweight push failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pulls every Health bodyweight sample from the last `days` and logs any DaGym doesn't
    /// already have (exact-timestamp dedupe via `WorkoutStore.bodyMeasurementDates()`), so the
    /// bodyweight chart and trend logic can be backed by full Health history, not just whatever
    /// `pullBodyweight()`'s single latest-reading pull happened to catch. Same toggle as
    /// `pullBodyweight`/`pushBodyweight` — one switch controls all of bodyweight sync.
    func pullBodyweightHistory(days: Int = 90) async {
        guard preferences.healthSyncBodyweight, isAvailable else { return }
        do {
            let since = Date().addingTimeInterval(-Double(days) * 86_400)
            let samples = try await healthStore.bodyMassHistory(from: since, to: Date())
            guard !samples.isEmpty else { return }
            let known = workoutStore.bodyMeasurementDates()
            var imported = false
            for sample in samples where !known.contains(sample.date) {
                workoutStore.logBodyweight(kg: sample.value, date: sample.date, source: "health")
                imported = true
            }
            if imported { lastSyncDate = Date() }
        } catch {
            healthLogger.error(
                "Bodyweight history pull failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Imports `HKWorkout` strength sessions logged in other apps (or the Watch) as backfilled
    /// `WorkoutModel`s, deduplicated by `WorkoutStore.importExternalWorkout` on `HKWorkout.uuid`.
    /// `HealthKitStore.externalStrengthWorkouts` has already filtered out anything DaGym wrote
    /// itself, so every sample reaching here is genuinely external.
    func pullExternalWorkouts(days: Int = 30) async {
        guard preferences.healthImportWorkouts, isAvailable else { return }
        do {
            let since = Date().addingTimeInterval(-Double(days) * 86_400)
            let external = try await healthStore.externalStrengthWorkouts(since: since)
            guard !external.isEmpty else { return }
            var imported = false
            for workout in external where workoutStore.importExternalWorkout(workout) != nil {
                imported = true
            }
            if imported { lastSyncDate = Date() }
        } catch {
            healthLogger.error(
                "External workout pull failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Registers Health's background-delivery observers for body mass and workouts, so new
    /// samples (weighed in on a smart scale, a workout logged on the Watch) get pulled in without
    /// the user opening Settings. Call once per launch, after `authorize()` has run at least once
    /// — an unauthorized registration just no-ops. Requires the HealthKit background-delivery
    /// entitlement (`project.yml`'s `com.apple.developer.healthkit.background-delivery`).
    func startObservingHealthChanges() async {
        guard isAvailable else { return }
        if preferences.healthSyncBodyweight {
            do {
                try await healthStore.observeBodyMassChanges { [weak self] in
                    Task { await self?.pullBodyweightHistory() }
                }
            } catch {
                healthLogger.error(
                    "Body mass observer registration failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        if preferences.healthImportWorkouts {
            do {
                try await healthStore.observeWorkoutChanges { [weak self] in
                    Task { await self?.pullExternalWorkouts() }
                }
            } catch {
                healthLogger.error(
                    "Workout observer registration failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// A rough active-energy estimate for `syncFinishedWorkout`, using the bodyweight recorded on
    /// the workout itself when there is one, falling back to the latest known measurement and
    /// finally a generic 80kg so a first-ever sync (before any bodyweight is logged) still works.
    private func estimatedEnergyKcal(start: Date, end: Date, bodyweightKg: Double?) -> Double {
        let bodyweight = bodyweightKg ?? workoutStore.latestBodyMeasurement()?.bodyweightKg ?? 80
        let durationSeconds = Int(end.timeIntervalSince(start))
        return HealthUnitConversion.estimatedActiveEnergyKcal(
            durationSeconds: durationSeconds, bodyweightKg: bodyweight
        )
    }
}
