import GymCore
import ActivityKit
import Foundation

/// Everything `WorkoutSession` knows about a rest-state change, handed to
/// `RestActivityController` through `WorkoutSession.onRestStateChange`. This type (unlike
/// `RestActivityAttributes`) references app-only concepts, so it stays out of the widget target.
struct RestState {
    var remaining: Int
    var total: Int
    var workoutTitle: String
    var exerciseName: String
    var setNumber: Int
    var setCount: Int
    var nextWeightKg: Double?
    var nextReps: Int?
    var fallbackNextLabel: String
    var isEnded: Bool
    var isSkipped: Bool

    /// "82.5 × 8" when the next step is a plain weight × reps set, else the session's own
    /// fallback text ("Next Bench Press" / "Last set done").
    var nextSetLabel: String {
        guard let nextWeightKg, let nextReps else { return fallbackNextLabel }
        return "\(WeightFormat.kg(nextWeightKg)) × \(nextReps)"
    }

    var setLabel: String { "Set \(setNumber) of \(setCount)" }
}

/// Owns the rest-timer Live Activity: starts one when rest begins, updates it on every state
/// change (rare — the countdown itself is timer-driven by `Text(timerInterval:)` inside the
/// widget, not by repeated updates from here), and ends it on skip or natural completion.
///
/// A future Watch/Widget-only intent that must run in the extension process (rather than the app
/// process, which `LiveActivityIntent` already gives us for free — see `RestIntents.swift`) would
/// need this mirrored into App Group storage. Not needed today.
@MainActor
final class RestActivityController {
    static let shared = RestActivityController()

    private var activity: ActivityHandle?

    /// `Activity` is documented as safe to use from any context but is not marked Sendable;
    /// boxing it lets the async ActivityKit calls leave the main actor without a diagnostic.
    private final class ActivityHandle: @unchecked Sendable {
        let activity: Activity<RestActivityAttributes>
        init(_ activity: Activity<RestActivityAttributes>) { self.activity = activity }
    }
    private weak var boundSession: WorkoutSession?
    private let notifications = RestNotificationScheduler()

    private init() {}

    /// Wires `session`'s rest-state hook to this controller and registers the App Intent
    /// callbacks those Lock Screen / Dynamic Island buttons invoke. Call once per Active Workout
    /// screen — see `ActiveWorkoutView+LiveActivity.swift`.
    func bind(to session: WorkoutSession) {
        boundSession = session
        session.onRestStateChange = { [weak self] state in self?.handle(state) }
        RestIntentTarget.addTime = { [weak session] in session?.adjustRest(by: 30) }
        RestIntentTarget.skip = { [weak session] in session?.skipRest() }
        RestIntentTarget.markSetDone = { [weak self] in self?.markNextSetDone() }
    }

    private func handle(_ state: RestState) {
        let endDate = Date().addingTimeInterval(TimeInterval(state.remaining))
        if state.isEnded {
            notifications.cancel()
            end(naturalEnd: !state.isSkipped, endDate: endDate)
            return
        }
        NotificationPermission.requestIfNeeded()
        notifications.schedule(endDate: endDate, nextSetLabel: state.nextSetLabel)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(
            state: RestActivityAttributes.ContentState(
                endDate: endDate, totalSeconds: state.total,
                nextSetLabel: state.nextSetLabel, setLabel: state.setLabel, isPaused: false
            ),
            staleDate: nil
        )
        if activity != nil {
            Task { await self.pushUpdate(content) }
        } else {
            start(state: state, content: content)
        }
    }

    // The Activity handle is not Sendable, so it never crosses an isolation boundary: these
    // helpers run on the main actor (the class's isolation) and only touch `self.activity`.
    private func pushUpdate(_ content: ActivityContent<RestActivityAttributes.ContentState>) async {
        guard let handle = activity else { return }
        await handle.activity.update(content)
    }

    private func finishActivity(policy: ActivityUIDismissalPolicy) async {
        if let handle = activity {
            await handle.activity.end(handle.activity.content, dismissalPolicy: policy)
        }
        activity = nil
    }

    private func start(state: RestState, content: ActivityContent<RestActivityAttributes.ContentState>) {
        let attributes = RestActivityAttributes(
            workoutTitle: state.workoutTitle, exerciseName: state.exerciseName
        )
        activity = (try? Activity.request(attributes: attributes, content: content)).map(ActivityHandle.init)
    }

    /// `.immediate` on skip; `.after(endDate + 5s)` on a natural end so "rest over" stays visible
    /// briefly before the activity clears itself.
    private func end(naturalEnd: Bool, endDate: Date) {
        guard activity != nil else { return }
        let policy: ActivityUIDismissalPolicy =
            naturalEnd ? .after(endDate.addingTimeInterval(5)) : .immediate
        Task { await self.finishActivity(policy: policy) }
    }

    /// "SET DONE" — completes the next not-yet-done set of the on-deck exercise directly from
    /// the Lock Screen / Dynamic Island, at its planned weight × reps.
    private func markNextSetDone() {
        guard let session = boundSession, let exerciseIndex = session.onDeckIndex,
              let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { !$0.isDone })
        else { return }
        let exerciseID = session.exercises[exerciseIndex].id
        let setID = session.exercises[exerciseIndex].sets[setIndex].id
        session.completeSet(exerciseID: exerciseID, setID: setID)
    }
}
