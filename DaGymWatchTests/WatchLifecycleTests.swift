import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// Start, finish, recovery and the summary — the edges where the wrist's own state meets the
/// shared store and HealthKit.
@MainActor
@Suite("WatchStore lifecycle")
struct WatchLifecycleTests {
    private func makeWatch(haptics: Bool = true) throws -> (WatchStore, ModelContainer) {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: container.mainContext, photoContext: nil)
        WatchSampleSeeder.seed(store: store)
        let preferences = WatchPreferences(defaults: WatchTestDefaults.fresh())
        preferences.haptics = haptics
        let watch = WatchStore(
            store: store, preferences: preferences, runtime: WatchWorkoutRuntime(isEnabled: false),
            snapshotSuite: WatchTestDefaults.fresh()
        )
        return (watch, container)
    }

    @Test("the summary is titled after the session that was done, not today's routine")
    func summaryTitleFromSession() throws {
        let (watch, container) = try makeWatch()
        watch.refreshHome()
        let today = try #require(watch.home.todaysRoutine)
        let other = try #require(watch.store.routines().first { $0.id != today.id })

        watch.start(routineID: other.id)
        let session = try #require(watch.session)
        let first = try #require(session.exercises.first)
        watch.logCurrentSet(exerciseID: first.id)
        watch.finish()

        #expect(watch.summary != nil)
        #expect(watch.summaryTitle == session.title)
        #expect(watch.summaryTitle != today.name)
        watch.dismissSummary()
        #expect(watch.summaryTitle == nil)
        withExtendedLifetime(container) {}
    }

    @Test("a resumed workout with two rows sharing an id adopts without trapping")
    func duplicateSetIDs() throws {
        let (watch, container) = try makeWatch()
        let bench = ExerciseInfo(
            name: "Bench", primary: [.chest], equipment: "barbell", loggingStyle: .weightReps
        )
        let shared = UUID()
        let one = SetEntry(id: shared, kind: .amrap, weightKg: 60, reps: 5)
        let two = SetEntry(id: shared, kind: .amrap, weightKg: 60, reps: 8)
        let entry = WorkoutExerciseEntry(exercise: bench, sets: [one, two])
        let session = WorkoutSession(title: "Merged", subtitle: "", startedAt: Date(), exercises: [entry])

        watch.adopt(session)

        #expect(watch.amrapTargets[shared] == 5)
        withExtendedLifetime(container) {}
    }

    @Test("a recovered HealthKit session is kept only for a workout this wrist started")
    func recoveredSessionGate() {
        var home = WatchHomeState()
        #expect(!WatchStore.shouldKeepRecoveredSession(home: home))
        home.resumableWorkoutID = UUID()
        home.resumableSourceDevice = "iPhone"
        #expect(!WatchStore.shouldKeepRecoveredSession(home: home))
        home.resumableSourceDevice = WatchStore.sourceDevice
        #expect(WatchStore.shouldKeepRecoveredSession(home: home))
    }

    @Test("refreshHome records where the resumable workout came from, and how many are open")
    func homeCarriesSourceAndCount() throws {
        let (watch, container) = try makeWatch()
        let routine = try #require(watch.store.todaysRoutine())
        watch.start(routineID: routine.id)
        let workoutID = try #require(watch.session?.workoutID)
        // Kill mid-workout: the model stays open with the wrist's stamp.
        watch.session = nil
        watch.stopTicking()

        watch.refreshHome()

        #expect(watch.home.resumableWorkoutID == workoutID)
        #expect(watch.home.resumableSourceDevice == WatchStore.sourceDevice)
        #expect(watch.home.unfinishedCount == 1)
        #expect(WatchStore.shouldKeepRecoveredSession(home: watch.home))
        withExtendedLifetime(container) {}
    }

    @Test("the injected preferences gate the haptics, not the shared instance")
    func hapticsFollowInjectedPreferences() throws {
        let (watch, container) = try makeWatch(haptics: false)
        #expect(Haptics.preferences === watch.preferences)
        #expect(!Haptics.preferences.haptics)
        watch.preferences.haptics = true
        #expect(Haptics.preferences.haptics)
        withExtendedLifetime(container) {}
    }

    @Test("the source device stamp is the one constant the gate and the start share")
    func sourceDeviceConstant() throws {
        let (watch, container) = try makeWatch()
        let routine = try #require(watch.store.todaysRoutine())
        watch.start(routineID: routine.id)
        let workoutID = try #require(watch.session?.workoutID)
        #expect(watch.store.workout(id: workoutID)?.sourceDevice == WatchStore.sourceDevice)
        let verdict = WatchStore.resumeGate(
            sourceDevice: WatchStore.sourceDevice, startedAt: Date(), lastLoggedAt: Date(), now: Date()
        )
        #expect(verdict == .resumable)
        withExtendedLifetime(container) {}
    }
}
