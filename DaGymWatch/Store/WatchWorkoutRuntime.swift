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
    /// True while `session` came from `adopt(recovered:)` rather than a start of our own, so
    /// `start` knows to end it instead of refusing: a lifter who taps Start rather than Resume
    /// must not have the new workout ride the old session's activity type and start date.
    private var isAdopted = false
    /// The start that is still awaiting HealthKit's authorisation sheet, if any. `end` and
    /// `discard` cancel it, so a workout discarded during that wait never leaves a strength
    /// session running behind nothing (and stealing the next workout's runtime).
    private var pendingStart = StartToken()
    /// Off for the sample store, the test host and any test that builds its own `WatchStore`:
    /// `requestAuthorization` would otherwise block on a permission sheet nobody can answer.
    private let isEnabled: Bool

    var isRunning: Bool { session != nil }

    /// The types the live data source collects for the workout. Read access is what lets the
    /// builder attach the heart-rate and active-energy samples the watch records during the
    /// session to the saved `HKWorkout`, so the Fitness app's card for it shows calories and
    /// average heart rate rather than blanks; the rings would fill either way (Apple Watch
    /// saves the energy samples itself while a session runs) but a strength workout with no
    /// numbers on its card reads as broken. Kept for that reason — see the usage description
    /// in project.yml.
    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)
    ]
    static let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

    init(isEnabled: Bool = !WatchLaunchFlags.isSample && !WatchLaunchFlags.isTestHost) {
        self.isEnabled = isEnabled
    }

    /// `resuming` keeps a recovered (adopted) session: after a kill mid-workout, Resume rides
    /// the HealthKit session watchOS kept alive, so the pre-kill heart-rate and energy stay in
    /// the saved workout. A fresh Start instead closes that session out, so the new workout gets
    /// one of its own rather than none at all.
    func start(isFreestyle: Bool, startedAt: Date, resuming: Bool = false) {
        guard isEnabled, HKHealthStore.isHealthDataAvailable(), !pendingStart.isPending else { return }
        if session != nil, isAdopted, !resuming { discard() }
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = isFreestyle ? .functionalStrengthTraining : .traditionalStrengthTraining
        configuration.locationType = .indoor
        let token = pendingStart.request()
        Task { await begin(configuration: configuration, startedAt: startedAt, token: token) }
    }

    private func begin(configuration: HKWorkoutConfiguration, startedAt: Date, token: Int) async {
        var started: HKWorkoutSession?
        do {
            try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
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
            isAdopted = false
            pendingStart.clear()
            session.startActivity(with: startedAt)
            started = session
            try await builder.beginCollection(at: startedAt)
        } catch {
            runtimeLogger.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
            pendingStart.clear()
            // `startActivity` already ran: without `end()` the session stays active behind
            // nothing and the next `HKWorkoutSession(...)` fails as "already active".
            started?.end()
            if let started { release(matching: ObjectIdentifier(started)) }
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
        isAdopted = true
        if !keep { discard() }
    }

    /// Ends the session and saves the workout so the rings get credit. The references are
    /// kept until the save has finished: Apple's sequence is `stopActivity`, wait for
    /// `.stopped`, then `endCollection` → `finishWorkout` → `end()` — releasing the session
    /// first would drop the background runtime while the save was still in flight.
    func end() {
        pendingStart.cancel()
        guard let session, builder != nil else { return }
        let id = ObjectIdentifier(session)
        session.stopActivity(with: Date())
        // Watchdog: if `.stopped` never arrives (a session still `.prepared`, a HealthKit
        // hiccup) the references would otherwise be held for the rest of the launch and every
        // later `start` would refuse. After the grace period, end and release regardless.
        Task { [weak self] in
            try? await Task.sleep(for: Self.stopWatchdog)
            guard let self, let session = self.session, ObjectIdentifier(session) == id else { return }
            runtimeLogger.error("HealthKit session never reported .stopped; ending it directly")
            session.end()
            self.release(matching: id)
        }
    }

    /// How long `end()` waits for `.stopped` before giving up on the delegate.
    static let stopWatchdog = Duration.seconds(10)

    /// The tail of `end()`, once the session has stopped. Keyed by identity rather than the
    /// session object: the delegate is nonisolated and `HKWorkoutSession` is not `Sendable`.
    private func finishAndRelease(matching id: ObjectIdentifier, at date: Date) async {
        guard let session, let builder, ObjectIdentifier(session) == id else { return }
        do {
            try await builder.endCollection(at: date)
            let workout = try await builder.finishWorkout()
            let minutes = workout.map { $0.duration / 60 } ?? 0
            runtimeLogger.info("Workout saved to Health: \(minutes, format: .fixed(precision: 1)) min")
        } catch {
            runtimeLogger.error("Workout save failed: \(error.localizedDescription, privacy: .public)")
        }
        session.end()
        release(matching: id)
    }

    /// A discarded workout is not exercise: end the session and drop the builder.
    func discard() {
        pendingStart.cancel()
        guard let session, let builder else { return }
        release(matching: ObjectIdentifier(session))
        session.end()
        Task {
            do {
                try await builder.endCollection(at: Date())
            } catch {
                runtimeLogger.error(
                    "Discard endCollection failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            builder.discardWorkout()
        }
    }

    /// Forgets `session` if it is still the one we hold — a later start may already have
    /// replaced it by the time an old session's callback arrives.
    private func release(matching id: ObjectIdentifier) {
        guard let session, ObjectIdentifier(session) == id else { return }
        self.session = nil
        builder = nil
        isAdopted = false
    }

    /// What a session-state change means for the runtime: our own `end()` reaches `.stopped`
    /// and must save; `.ended` without us asking (HealthKit or the system closed it) means the
    /// references are dead and a later `start` must be allowed to open a fresh session.
    enum StateReaction: Equatable {
        case save, release, none
    }

    nonisolated static func reaction(to state: HKWorkoutSessionState) -> StateReaction {
        switch state {
        case .stopped: .save
        case .ended: .release
        default: .none
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
    ) {
        let id = ObjectIdentifier(workoutSession)
        switch Self.reaction(to: toState) {
        case .save:
            Task { @MainActor in await self.finishAndRelease(matching: id, at: date) }
        case .release:
            Task { @MainActor in self.release(matching: id) }
        case .none:
            break
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        runtimeLogger.error("Workout session error: \(error.localizedDescription, privacy: .public)")
        // A failed session is finished as far as HealthKit is concerned; holding on to it
        // would refuse every later start for the rest of the launch.
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in self.release(matching: id) }
    }
}
