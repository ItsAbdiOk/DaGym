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

    var isRunning: Bool { session != nil }

    func start(isFreestyle: Bool, startedAt: Date) {
        guard !WatchLaunchFlags.isSample, HKHealthStore.isHealthDataAvailable(), session == nil else {
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = isFreestyle ? .functionalStrengthTraining : .traditionalStrengthTraining
        configuration.locationType = .indoor
        Task { await begin(configuration: configuration, startedAt: startedAt) }
    }

    private func begin(configuration: HKWorkoutConfiguration, startedAt: Date) async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: configuration
            )
            session.delegate = self
            self.session = session
            self.builder = builder
            session.startActivity(with: startedAt)
            try await builder.beginCollection(at: startedAt)
        } catch {
            runtimeLogger.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
            self.session = nil
            self.builder = nil
        }
    }

    /// Ends the session and saves the workout so the rings get credit. `volumeKg` is not
    /// written anywhere — HealthKit has no field for it and the store already has it.
    func end(volumeKg: Double) {
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
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.end()
        Task {
            try? await builder.endCollection(at: Date())
            builder.discardWorkout()
        }
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
