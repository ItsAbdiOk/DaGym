import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// The watch and the phone mirror one `WorkoutModel` through CloudKit, and `sync` on either
/// side deletes rows the other added. So Home may only offer "Resume" for a workout this wrist
/// started, or one another device has plainly abandoned — never for a session the phone is
/// logging right now.
@MainActor
@Suite("Watch resume gate")
struct WatchResumeGateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a workout this wrist started is always resumable")
    func watchOwnIsResumable() {
        let verdict = WatchStore.resumeGate(
            sourceDevice: "Apple Watch", startedAt: now.addingTimeInterval(-30), lastLoggedAt: now, now: now
        )
        #expect(verdict == .resumable)
    }

    @Test("a phone workout with a set logged in the last ten minutes is live elsewhere")
    func phoneLiveIsNotOffered() {
        let verdict = WatchStore.resumeGate(
            sourceDevice: "iPhone", startedAt: now.addingTimeInterval(-1_800),
            lastLoggedAt: now.addingTimeInterval(-120), now: now
        )
        #expect(verdict == .liveElsewhere)
        // Just started, nothing logged yet: the start itself is the last activity.
        let fresh = WatchStore.resumeGate(
            sourceDevice: "iPhone", startedAt: now.addingTimeInterval(-60), lastLoggedAt: nil, now: now
        )
        #expect(fresh == .liveElsewhere)
    }

    @Test("a phone workout idle for ten minutes was abandoned and may be picked up")
    func phoneStaleIsResumable() {
        let verdict = WatchStore.resumeGate(
            sourceDevice: "iPhone", startedAt: now.addingTimeInterval(-3_600),
            lastLoggedAt: now.addingTimeInterval(-600), now: now
        )
        #expect(verdict == .resumable)
    }

    @Test("Home shows a phone session in progress instead of offering to resume it")
    func homeShowsInProgressElsewhere() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let phone = WorkoutStore(context: container.mainContext, photoContext: nil)
        WatchSampleSeeder.seed(store: phone)
        let watch = WatchStore(
            store: WorkoutStore(context: container.mainContext, photoContext: nil),
            preferences: WatchPreferences(defaults: WatchTestDefaults.fresh()),
            runtime: WatchWorkoutRuntime(isEnabled: false)
        )
        let routine = try #require(phone.todaysRoutine())
        let live = phone.startWorkout(routineIDs: [routine.id])
        live.exercises[0].sets[0].isDone = true
        phone.sync(session: live)

        watch.refreshHome()

        #expect(watch.home.resumableWorkoutID == nil)
        #expect(watch.home.inProgressElsewhereTitle == routine.name)

        // Once the phone has been silent for ten minutes the same workout is offered.
        watch.refreshHome(now: Date().addingTimeInterval(11 * 60))
        #expect(watch.home.resumableWorkoutID == live.workoutID)
        #expect(watch.home.inProgressElsewhereTitle == nil)
        withExtendedLifetime(container) {}
    }
}
