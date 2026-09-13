import GymCore
import Foundation

/// Everything `WorkoutSession` knows about a rest-state change, handed to
/// `RestActivityController` through `WorkoutSession.onRestStateChange`. This type (unlike
/// `RestActivityAttributes`) references app-only concepts, so it stays out of the widget target.
struct RestState {
    var remaining: Int
    var total: Int
    /// The wall-clock moment the rest ends — the same instant the in-app pill counts to.
    var endDate: Date
    var workoutTitle: String
    var exerciseName: String
    var setNumber: Int
    var setCount: Int
    var nextWeightKg: Double?
    var nextReps: Int?
    var fallbackNextLabel: String
    var isEnded: Bool
    var isSkipped: Bool

    /// "82.5 kg × 8" / "180 lb × 8" when the next step is a plain weight × reps set, else the
    /// session's own fallback text ("Next Bench Press" / "Last set done").
    func nextSetLabel(unit: WeightUnit) -> String {
        guard let nextWeightKg, let nextReps else { return fallbackNextLabel }
        return "\(unit.format(kg: nextWeightKg)) \(unit.symbol) × \(nextReps)"
    }

    var setLabel: String { "Set \(setNumber) of \(setCount)" }
}

/// How a rest activity leaves the Lock Screen — mirrors the two `ActivityUIDismissalPolicy`
/// cases the app uses, without pulling ActivityKit into the controller or its tests.
enum RestActivityDismissal: Equatable {
    case immediate
    case after(Date)
}

/// The ActivityKit surface `RestActivityController` drives, so tests can swap in a recorder and
/// assert *that* an activity was started, updated or ended rather than poking the real system.
/// `ActivityKitRestBackend` is the production implementation.
@MainActor
protocol RestActivityBackend: AnyObject {
    var areActivitiesEnabled: Bool { get }
    /// True while an activity started by this controller is showing.
    var hasActivity: Bool { get }
    /// Ends every rest activity left over from a previous process (crash, jetsam, reboot) so a
    /// relaunch never stacks a second banner on top of a stale one.
    func endStaleActivities()
    func start(attributes: RestActivityAttributes, state: RestActivityAttributes.ContentState)
    func update(state: RestActivityAttributes.ContentState)
    func end(_ dismissal: RestActivityDismissal)
}

/// Owns the rest-timer Live Activity: starts one when rest begins, updates it on every state
/// change (rare — the countdown itself is timer-driven by `Text(timerInterval:)` inside the
/// widget, not by repeated updates from here), and ends it on skip, natural completion, or when
/// the workout itself finishes (`endNow()`).
///
/// A future Watch/Widget-only intent that must run in the extension process (rather than the app
/// process, which `LiveActivityIntent` already gives us for free — see `RestIntents.swift`) would
/// need this mirrored into App Group storage. Not needed today.
@MainActor
final class RestActivityController {
    static let shared = RestActivityController()

    private let backend: any RestActivityBackend
    private let notifications: RestNotificationScheduler
    private let authorizer: any RestNotificationAuthorizing
    private weak var boundSession: WorkoutSession?
    private var weightUnit: () -> WeightUnit = { .kg }
    private var onSessionMutation: (() -> Void)?
    /// End date of the rest whose notification is (being) scheduled; a skip or finish that lands
    /// while the permission prompt is still up clears it so the late schedule is dropped.
    private var scheduledEndDate: Date?
    /// The in-flight permission-then-schedule step, exposed so tests can await it.
    private(set) var pendingSchedule: Task<Void, Never>?

    init(
        backend: any RestActivityBackend = ActivityKitRestBackend(),
        notifications: RestNotificationScheduler = RestNotificationScheduler(),
        authorizer: any RestNotificationAuthorizing = SystemNotificationAuthorizer()
    ) {
        self.backend = backend
        self.notifications = notifications
        self.authorizer = authorizer
        backend.endStaleActivities()
    }

    /// Wires `session`'s rest-state hook to this controller and registers the App Intent
    /// callbacks those Lock Screen / Dynamic Island buttons invoke. `weightUnit` is read at each
    /// rest so the Lock Screen speaks the user's unit; `onSessionMutation` runs after a Lock
    /// Screen "SET DONE" so the change is persisted like every in-app mutation. Call once per
    /// Active Workout screen — see `ActiveWorkoutView+LiveActivity.swift`.
    func bind(
        to session: WorkoutSession, weightUnit: @escaping () -> WeightUnit = { .kg },
        onSessionMutation: (() -> Void)? = nil
    ) {
        boundSession = session
        self.weightUnit = weightUnit
        self.onSessionMutation = onSessionMutation
        session.onRestStateChange = { [weak self] state in self?.handle(state) }
        RestIntentTarget.addTime = { [weak session] in session?.adjustRest(by: 30) }
        RestIntentTarget.skip = { [weak session] in session?.skipRest() }
        RestIntentTarget.markSetDone = { [weak self] in self?.markNextSetDone() }
    }

    /// The workout is over (finished, discarded, or its screen went away): take the banner down
    /// now, drop the pending "Rest over" alert, and stop the Lock Screen buttons reaching a
    /// session that no longer exists.
    func endNow() {
        pendingSchedule?.cancel()
        scheduledEndDate = nil
        notifications.cancel()
        backend.end(.immediate)
        if let session = boundSession { session.onRestStateChange = nil }
        boundSession = nil
        onSessionMutation = nil
        RestIntentTarget.addTime = nil
        RestIntentTarget.skip = nil
        RestIntentTarget.markSetDone = nil
    }

    private func handle(_ state: RestState) {
        if state.isEnded {
            pendingSchedule?.cancel()
            scheduledEndDate = nil
            notifications.cancel()
            end(naturalEnd: !state.isSkipped, endDate: state.endDate)
            return
        }
        let nextSetLabel = state.nextSetLabel(unit: weightUnit())
        scheduleNotification(endDate: state.endDate, nextSetLabel: nextSetLabel)
        guard backend.areActivitiesEnabled else { return }
        let content = RestActivityAttributes.ContentState(
            endDate: state.endDate, totalSeconds: state.total,
            nextSetLabel: nextSetLabel, setLabel: state.setLabel
        )
        if backend.hasActivity {
            backend.update(state: content)
        } else {
            let attributes = RestActivityAttributes(
                workoutTitle: state.workoutTitle, exerciseName: state.exerciseName
            )
            backend.start(attributes: attributes, state: content)
        }
    }

    /// Waits for the permission prompt (a no-op after the first rest) before scheduling, so the
    /// very first rest gets its alert too. Dropped if the rest ended while the prompt was up.
    private func scheduleNotification(endDate: Date, nextSetLabel: String) {
        pendingSchedule?.cancel()
        scheduledEndDate = endDate
        let authorizer = authorizer
        pendingSchedule = Task { [weak self] in
            await authorizer.awaitAuthorization()
            guard let self, !Task.isCancelled, scheduledEndDate == endDate else { return }
            notifications.schedule(endDate: endDate, nextSetLabel: nextSetLabel)
        }
    }

    /// `.immediate` on skip; `.after(endDate + 5s)` on a natural end so "rest over" stays visible
    /// briefly before the activity clears itself.
    private func end(naturalEnd: Bool, endDate: Date) {
        guard backend.hasActivity else { return }
        backend.end(naturalEnd ? .after(endDate.addingTimeInterval(5)) : .immediate)
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
        onSessionMutation?()
    }
}
