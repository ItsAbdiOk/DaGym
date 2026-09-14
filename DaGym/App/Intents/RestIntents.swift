import ActivityKit
import AppIntents

/// Runtime hook the app wires up in `RestActivityController.bind(to:)` so these intents can reach
/// live workout state without App Group storage. `LiveActivityIntent` conformance makes iOS run
/// `perform()` in the *app's* process even though the button lives in the widget extension's UI,
/// which is exactly why a plain closure works here — no shared container needed.
///
/// A future intent that has to run in the extension process itself (e.g. a Watch complication or
/// a Home Screen widget button with no app in the loop) would need this mirrored into an App
/// Group instead of an in-process closure.
@MainActor
enum RestIntentTarget {
    static var addTime: (() -> Void)?
    static var skip: (() -> Void)?
    static var markSetDone: (() -> Void)?

    /// Runs `target` if the session that registered it is still around, and otherwise takes the
    /// banner down.
    ///
    /// These closures only exist in the process that started the rest. If iOS jetsams the app
    /// mid-rest, the Lock Screen banner survives but every closure is gone — and `+30S` / `SKIP` /
    /// `SET DONE` used to do nothing at all, silently, with the banner still sitting there. A
    /// button that cannot do its job must at least clear the thing it is attached to.
    static func run(_ target: (() -> Void)?) {
        if let target {
            target()
        } else {
            orphanFallback()
        }
    }

    /// What a button does when its session is gone. Overridable so `LiveActivityControllerTests`
    /// can watch the fallback fire without a real Live Activity.
    static var orphanFallback: @MainActor () -> Void = { endAllActivities() }

    private static func endAllActivities() {
        for activity in Activity<RestActivityAttributes>.activities {
            let handle = ActivityEndHandle(activity)
            Task { await handle.activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// `Activity` is documented as safe to use from any context but is not marked `Sendable`;
    /// boxing it lets the async `end` leave the main actor without a diagnostic (same trick as
    /// `ActivityKitRestBackend.ActivityHandle`, which this file can't see from the widget target).
    private final class ActivityEndHandle: @unchecked Sendable {
        let activity: Activity<RestActivityAttributes>
        init(_ activity: Activity<RestActivityAttributes>) { self.activity = activity }
    }
}

/// "+30S" on the Lock Screen / Dynamic Island rest timer.
struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 30 Seconds"

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentTarget.run(RestIntentTarget.addTime)
        return .result()
    }
}

/// "SKIP" — ends the rest timer immediately.
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Rest"

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentTarget.run(RestIntentTarget.skip)
        return .result()
    }
}

/// "SET DONE" — marks the on-deck set complete at its planned weight × reps without opening the
/// app.
struct MarkSetDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Set Done"

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentTarget.run(RestIntentTarget.markSetDone)
        return .result()
    }
}
