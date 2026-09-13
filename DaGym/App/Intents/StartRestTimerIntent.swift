import AppIntents

/// Set by `StartRestTimerIntent.perform()` (running in the app's process once it opens),
/// consumed by `RootView` on appear. This is the one-line hookup a Control Center button needs:
/// unlike the Live Activity intents in `RestIntents.swift`, this one has no running session to
/// call into yet, so it can't use an in-process closure — it has to wait for the app to open.
@MainActor
enum PendingIntentAction {
    private static var startRestTimerRequested = false

    static func requestStartRestTimer() {
        startRestTimerRequested = true
    }

    /// Returns whether a rest timer was requested, clearing the flag so it only fires once.
    static func consumeStartRestTimer() -> Bool {
        defer { startRestTimerRequested = false }
        return startRestTimerRequested
    }
}

/// Control Center "Rest timer" button (`RestTimerControl`, iOS 18+ `ControlWidget`). Opens the
/// app and starts a default-length rest — see `RootView.startPendingRestTimerIfNeeded()`.
struct StartRestTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Rest Timer"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingIntentAction.requestStartRestTimer()
        return .result()
    }
}
