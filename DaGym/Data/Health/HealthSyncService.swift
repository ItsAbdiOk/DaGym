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
    /// makes a repeat call a no-op rather than a duplicate `HKWorkout`.
    func syncFinishedWorkout(_ workout: WorkoutModel) async {
        guard preferences.healthWriteWorkouts, isAvailable, workout.healthKitID == nil,
              let endedAt = workout.endedAt else { return }
        let sets = (workout.exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
        let volumeKg = sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        let workoutID = workout.id
        let input = HealthWorkoutInput(
            start: workout.startedAt, end: endedAt, title: workout.title,
            routineName: workout.routineName, workoutID: workoutID.uuidString,
            setCount: sets.count, volumeKg: volumeKg
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
}
