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
    @Test("the summary is titled after the session that was done, not today's routine")
    func summaryTitleFromSession() throws {
        let fixture = try makeWatchFixture()
        let watch = fixture.watch
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
        withExtendedLifetime(fixture) {}
    }

    @Test("a resumed workout with two rows sharing an id adopts without trapping")
    func duplicateSetIDs() throws {
        let fixture = try makeWatchFixture()
        let watch = fixture.watch
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
        withExtendedLifetime(fixture) {}
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
        let fixture = try makeWatchFixture()
        let watch = fixture.watch
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
        withExtendedLifetime(fixture) {}
    }

    @Test("the injected preferences gate the haptics, not the shared instance")
    func hapticsFollowInjectedPreferences() throws {
        let fixture = try makeWatchFixture(haptics: false)
        let watch = fixture.watch
        #expect(Haptics.preferences === watch.preferences)
        #expect(!Haptics.preferences.haptics)
        watch.preferences.haptics = true
        #expect(Haptics.preferences.haptics)
        withExtendedLifetime(fixture) {}
    }

    @Test("the source device stamp is the one constant the gate and the start share")
    func sourceDeviceConstant() throws {
        let fixture = try makeWatchFixture()
        let watch = fixture.watch
        let routine = try #require(watch.store.todaysRoutine())
        watch.start(routineID: routine.id)
        let workoutID = try #require(watch.session?.workoutID)
        #expect(watch.store.workout(id: workoutID)?.sourceDevice == WatchStore.sourceDevice)
        let verdict = WatchStore.resumeGate(
            sourceDevice: WatchStore.sourceDevice, startedAt: Date(), lastLoggedAt: Date(), now: Date()
        )
        #expect(verdict == .resumable)
        withExtendedLifetime(fixture) {}
    }
}
