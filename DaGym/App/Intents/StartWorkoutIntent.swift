import AppIntents

/// Set by `StartWorkoutIntent.perform()` once it opens the app, consumed by `RootView` on
/// appear — the same "flag now, act after launch" pattern `PendingIntentAction`
/// (`StartRestTimerIntent.swift`) uses, kept as a sibling type since that file "stays" per the
/// intents brief rather than being extended.
@MainActor
enum PendingWorkoutIntentAction {
    private static var startWorkoutRequested = false

    static func requestStartWorkout() {
        startWorkoutRequested = true
    }

    /// Returns whether a workout start was requested, clearing the flag so it only fires once.
    static func consumeStartWorkout() -> Bool {
        defer { startWorkoutRequested = false }
        return startWorkoutRequested
    }
}

/// "Start today's workout" Siri Shortcut / App Intent (plan.md §6.8, voice-logging-plan.md §6.1
/// `StartWorkoutIntent`). Opens the app; `RootView` then starts today's scheduled routine (or
/// leaves an already-in-progress session alone) the same way tapping "Start" on Home does.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Workout"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingWorkoutIntentAction.requestStartWorkout()
        return .result()
    }
}
