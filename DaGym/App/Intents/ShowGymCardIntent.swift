import AppIntents

/// Set by `ShowGymCardIntent.perform()` once it opens the app, consumed by `RootView` the same
/// way `PendingWorkoutIntentAction` is — flag now, present `GymCardSheet` after launch.
@MainActor
enum PendingGymCardIntentAction {
    private static var showGymCardRequested = false

    static func requestShowGymCard() {
        showGymCardRequested = true
    }

    /// Returns whether the card was requested, clearing the flag so it only fires once.
    static func consumeShowGymCard() -> Bool {
        defer { showGymCardRequested = false }
        return showGymCardRequested
    }
}

/// "Show gym card" Siri Shortcut / App Intent (features.md adopt 6). Opens the app on the
/// check-in card so a Lock Screen shortcut or Action button gets the lifter through the gate
/// without hunting for the screen.
struct ShowGymCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Gym Card"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingGymCardIntentAction.requestShowGymCard()
        return .result()
    }
}
