import AppIntents

/// Set by `ShowGymCardIntent.perform()` once it opens the app, consumed by `RootView` the same
/// way `PendingWorkoutIntentAction` is — flag now, present `GymCardSheet` after launch.
@MainActor
enum PendingGymCardIntentAction {
    static func requestShowGymCard() {
        PendingIntentHandoff.shared.request(.showGymCard)
    }

    /// Returns whether the card was requested, clearing it so it only fires once.
    static func consumeShowGymCard() -> Bool {
        PendingIntentHandoff.shared.consume(.showGymCard)
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
