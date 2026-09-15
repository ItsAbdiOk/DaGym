import Foundation
import HealthKit
import os

private let runtimeLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "watch-runtime")

/// The `HKWorkoutSession` behind every watch workout. Its only jobs are background runtime
/// (the rest timer and its haptics keep running with the wrist down) and ring credit: on
/// finish the `HKWorkout` is saved with the session's own start and end. Heart rate and
/// energy stay in HealthKit — nothing this type sees is written to the SwiftData store
/// (App Store Guideline 5.1.3). Traditional strength training for a routine, functional
/// strength training for freestyle.
@MainActor
final class WatchWorkoutRuntime: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The start that is still awaiting HealthKit's authorisation sheet, if any. `end` and
    /// `discard` cancel it, so a workout discarded during that wait never leaves a strength
    /// session running behind nothing (and stealing the next workout's runtime).
    private var pendingStart = StartToken()
    /// Off for the sample store, the test host and any test that builds its own `WatchStore`:
    /// `requestAuthorization` would otherwise block on a permission sheet nobody can answer.
    private let isEnabled: Bool

    var isRunning: Bool { session != nil }

    init(isEnabled: Bool = !WatchLaunchFlags.isSample && !WatchLaunchFlags.isTestHost) {
        self.isEnabled = isEnabled
    }

    func start(isFreestyle: Bool, startedAt: Date) {
        guard isEnabled, HKHealthStore.isHealthDataAvailable(), session == nil, !pendingStart.isPending else {
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = isFreestyle ? .functionalStrengthTraining : .traditionalStrengthTraining
        configuration.locationType = .indoor
        let token = pendingStart.request()
        Task { await begin(configuration: configuration, startedAt: startedAt, token: token) }
    }

    private func begin(configuration: HKWorkoutConfiguration, startedAt: Date, token: Int) async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            // The workout was ended or discarded while the sheet was up: nothing to run for.
            guard pendingStart.isCurrent(token) else { return }
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: configuration
            )
            session.delegate = self
            self.session = session
            self.builder = builder
            pendingStart.clear()
            session.startActivity(with: startedAt)
            try await builder.beginCollection(at: startedAt)
        } catch {
            runtimeLogger.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
            pendingStart.clear()
            self.session = nil
            self.builder = nil
        }
    }

    /// Re-attaches to a session watchOS kept running after DaGym was killed mid-workout
    /// (`WKApplicationDelegate.handleActiveWorkoutRecovery`). With it adopted, "Resume" carries
    /// on with background runtime instead of failing to open a second session next to the
    /// orphan. `keep` false ends it straight away — nothing in the store to run for.
    func adopt(recovered session: HKWorkoutSession, keep: Bool) {
        guard isEnabled, self.session == nil else { return }
        pendingStart.clear()
        session.delegate = self
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore, workoutConfiguration: session.workoutConfiguration
        )
        self.session = session
        self.builder = builder
        if !keep { discard() }
    }

    /// Ends the session and saves the workout so the rings get credit. `volumeKg` is not
    /// written anywhere — HealthKit has no field for it and the store already has it.
    func end(volumeKg: Double) {
        pendingStart.cancel()
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.end()
        Task {
            do {
                try await builder.endCollection(at: Date())
                _ = try await builder.finishWorkout()
            } catch {
                runtimeLogger.error("Workout save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A discarded workout is not exercise: end the session and drop the builder.
    func discard() {
        pendingStart.cancel()
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.end()
        Task {
            try? await builder.endCollection(at: Date())
            builder.discardWorkout()
        }
    }

    /// One outstanding start at a time. `request` hands out a token; the start that holds it
    /// may only go ahead while it `isCurrent` — `cancel` (from `end`/`discard`) retires it and
    /// `clear` marks it done. A later `request` retires any earlier token too.
    struct StartToken {
        private var current: Int?
        private var last = 0

        var isPending: Bool { current != nil }

        mutating func request() -> Int {
            last += 1
            current = last
            return last
        }

        func isCurrent(_ token: Int) -> Bool { current == token }

        mutating func cancel() { current = nil }

        mutating func clear() { current = nil }
    }
}

extension WatchWorkoutRuntime: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState, date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        runtimeLogger.error("Workout session error: \(error.localizedDescription, privacy: .public)")
    }
}
