import AppIntents

/// Set by `StartWorkoutIntent.perform()` once it opens the app, consumed by `RootView` on
/// appear — the same "queue now, act after launch" pattern `PendingIntentAction`
/// (`StartRestTimerIntent.swift`) uses, kept as a sibling type since that file "stays" per the
/// intents brief rather than being extended.
@MainActor
enum PendingWorkoutIntentAction {
    static func requestStartWorkout() {
        PendingIntentHandoff.shared.request(.startWorkout)
    }

    /// Returns whether a workout start was requested, clearing it so it only fires once.
    static func consumeStartWorkout() -> Bool {
        PendingIntentHandoff.shared.consume(.startWorkout)
    }
}

/// "Start today's workout" Siri Shortcut / App Intent (plan.md §6.8, voice-logging-plan.md §6.1
/// `StartWorkoutIntent`). Opens the app (`openAppWhenRun`): a workout is a live session with a
/// rest timer, HealthKit workout and Live Activity behind it, none of which should start
/// headless — `RootView` starts today's scheduled routine (or leaves an already-in-progress
/// session alone) the same way tapping "Start" on Home does. The dialog names that routine so
/// Siri says "Starting Push Day A" rather than going silent while the app comes up; it is read
/// through `IntentStoreAccess` and falls back to a generic line when no store is reachable.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Workout"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingWorkoutIntentAction.requestStartWorkout()
        return .result(dialog: IntentDialog(stringLiteral: Self.dialog()))
    }

    /// `RootView` resolves the session itself (`startPendingWorkout`); this previews the same
    /// decision for the dialog: an unfinished workout is continued, today's routine is started,
    /// and a rest day starts a freestyle session.
    @MainActor
    static func dialog(now: Date = Date()) -> String {
        guard let store = IntentStoreAccess.makeStore() else { return "Starting your workout." }
        if let unfinished = store.unfinishedWorkouts().first {
            return IntentFormatting.continueWorkoutDialog(
                title: unfinished.title.isEmpty ? "your workout" : unfinished.title
            )
        }
        let calendar = IntentStoreAccess.preferences().trainingCalendar
        return IntentFormatting.startWorkoutDialog(
            routineName: store.todaysRoutine(calendar: calendar, now: now)?.name
        )
    }
}
