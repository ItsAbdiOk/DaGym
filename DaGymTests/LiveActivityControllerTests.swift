import Foundation
import GymCore
import Testing
import UserNotifications

@testable import DaGym

/// Records what the controller asked ActivityKit to do, so the tests assert lifecycle decisions
/// (start, update, end-with-policy, stale cleanup) without a device or a real activity.
@MainActor
private final class FakeActivityBackend: RestActivityBackend {
    var areActivitiesEnabled = true
    private(set) var hasActivity = false
    private(set) var staleCleanups = 0
    private(set) var started: [RestActivityAttributes.ContentState] = []
    private(set) var updated: [RestActivityAttributes.ContentState] = []
    private(set) var ended: [RestActivityDismissal] = []

    /// Simulates an activity left behind by a previous process.
    var hasStaleActivity = false

    func endStaleActivities() {
        staleCleanups += 1
        hasStaleActivity = false
    }

    func start(attributes: RestActivityAttributes, state: RestActivityAttributes.ContentState) {
        hasActivity = true
        started.append(state)
    }

    func update(state: RestActivityAttributes.ContentState) {
        updated.append(state)
    }

    func end(_ dismissal: RestActivityDismissal) {
        hasActivity = false
        ended.append(dismissal)
    }
}

private final class FakeNotificationCenter: RestNotificationCenter {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []

    func add(_ request: UNNotificationRequest) { addedRequests.append(request) }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }
}

private struct InstantAuthorizer: RestNotificationAuthorizing {
    func awaitAuthorization() async {}
}

@MainActor
@Suite("RestActivityController lifecycle")
struct LiveActivityControllerTests {
    @MainActor
    private struct Harness {
        let backend = FakeActivityBackend()
        let center = FakeNotificationCenter()
        let controller: RestActivityController
        let session: WorkoutSession

        init(stale: Bool = false, unit: WeightUnit = .kg) {
            backend.hasStaleActivity = stale
            controller = RestActivityController(
                backend: backend, notifications: RestNotificationScheduler(center: center),
                authorizer: InstantAuthorizer()
            )
            let exercise = ExerciseInfo(
                name: "Bench Press", primary: [.chest], equipment: "Barbell", restSeconds: 90
            )
            let sets = [
                SetEntry(kind: .working, weightKg: 80, reps: 8),
                SetEntry(kind: .working, weightKg: 80, reps: 8)
            ]
            session = WorkoutSession(
                title: "Push", subtitle: "", startedAt: Date(),
                exercises: [WorkoutExerciseEntry(exercise: exercise, sets: sets)]
            )
            controller.bind(to: session, weightUnit: { unit })
        }

        func awaitScheduling() async { await controller.pendingSchedule?.value }
    }

    @Test("init ends any activity a previous process left behind")
    func initEndsStaleActivity() {
        let harness = Harness(stale: true)

        #expect(harness.backend.staleCleanups == 1)
        #expect(harness.backend.hasStaleActivity == false)
    }

    @Test("starting rest starts one activity and schedules the alert once permission resolves")
    func restStartsActivityAndSchedules() async {
        let harness = Harness()

        harness.session.startRest(seconds: 90, after: 0, set: 0)
        await harness.awaitScheduling()

        #expect(harness.backend.started.count == 1)
        #expect(harness.backend.hasActivity)
        #expect(harness.center.addedRequests.count == 1)
        #expect(harness.backend.started.first?.endDate == harness.session.restEndDate)
    }

    @Test("endNow (finish/discard) ends the activity immediately and cancels the alert")
    func endNowEndsAndCancels() async {
        let harness = Harness()
        harness.session.startRest(seconds: 90, after: 0, set: 0)
        await harness.awaitScheduling()
        let cancelsBefore = harness.center.removedIdentifiers.count

        harness.controller.endNow()

        #expect(harness.backend.ended == [.immediate])
        #expect(!harness.backend.hasActivity)
        #expect(harness.center.removedIdentifiers.count == cancelsBefore + 1)
        #expect(RestIntentTarget.skip == nil)
        #expect(RestIntentTarget.markSetDone == nil)
    }

    @Test("endNow while the permission prompt is still up drops the pending alert")
    func endNowDropsPendingSchedule() async {
        let harness = Harness()
        harness.session.startRest(seconds: 90, after: 0, set: 0)

        harness.controller.endNow()
        await harness.awaitScheduling()

        #expect(harness.center.addedRequests.isEmpty)
    }

    @Test("a skipped rest ends immediately; a natural end lingers 5 s past the end date")
    func skipAndNaturalEndPolicies() async {
        let harness = Harness()
        harness.session.startRest(seconds: 90, after: 0, set: 0)
        harness.session.skipRest()
        #expect(harness.backend.ended == [.immediate])

        harness.session.startRest(seconds: 5, after: 0, set: 0)
        let endDate = harness.session.restEndDate ?? Date()
        harness.session.now = { Date().addingTimeInterval(10) }
        harness.session.tickRest()

        #expect(harness.backend.ended.count == 2)
        #expect(harness.backend.ended.last == RestActivityDismissal.after(endDate.addingTimeInterval(5)))
    }

    @Test("Lock Screen SET DONE completes the set and asks the view to persist it")
    func markSetDoneSyncs() {
        let harness = Harness()
        var syncs = 0
        harness.controller.bind(to: harness.session, onSessionMutation: { syncs += 1 })

        RestIntentTarget.markSetDone?()

        #expect(harness.session.exercises[0].sets[0].isDone)
        #expect(syncs == 1)
        harness.controller.endNow()
    }

    @Test("the Lock Screen next-set label speaks the user's unit")
    func nextSetLabelInLb() async {
        let harness = Harness(unit: .lb)

        harness.session.startRest(seconds: 90, after: 0, set: 0)
        await harness.awaitScheduling()

        let expected = "\(WeightUnit.lb.format(kg: 80)) lb × 8"
        #expect(harness.backend.started.first?.nextSetLabel == expected)
        #expect(harness.center.addedRequests.first?.content.body == "Next: \(expected)")
        harness.controller.endNow()
    }

    @Test("RestState.nextSetLabel formats in the given unit and falls back to the session's text")
    func restStateLabel() {
        var state = RestState(
            remaining: 60, total: 60, endDate: Date(), workoutTitle: "Push", exerciseName: "Bench",
            setNumber: 1, setCount: 3, nextWeightKg: 80, nextReps: 8, fallbackNextLabel: "Last set done",
            isEnded: false, isSkipped: false
        )
        #expect(state.nextSetLabel(unit: .kg) == "80 kg × 8")
        #expect(state.nextSetLabel(unit: .lb) == "\(WeightUnit.lb.format(kg: 80)) lb × 8")

        state.nextWeightKg = nil
        #expect(state.nextSetLabel(unit: .lb) == "Last set done")
    }
}
