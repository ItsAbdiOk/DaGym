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
}

/// "+30S" on the Lock Screen / Dynamic Island rest timer.
struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 30 Seconds"

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentTarget.addTime?()
        return .result()
    }
}

/// "SKIP" — ends the rest timer immediately.
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Rest"

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentTarget.skip?()
        return .result()
    }
}

/// "SET DONE" — marks the on-deck set complete at its planned weight × reps without opening the
/// app.
struct MarkSetDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Set Done"

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentTarget.markSetDone?()
        return .result()
    }
}
