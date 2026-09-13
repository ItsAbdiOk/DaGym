import AppIntents

/// Siri phrase catalogue (plan.md §6.8 "App Intents / Shortcuts", voice-logging-plan.md §6.3).
/// Every phrase includes `\(.applicationName)`, and each carries at most one parameter — always
/// an `AppEntity`/`AppEnum` (a free `String`, like `LogBodyweightIntent.weight`, can't be inlined
/// in a phrase, so that intent gets no parameter in its phrases and Siri asks for it after).
struct DaGymShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start today's workout in \(.applicationName)",
                "Start my workout in \(.applicationName)"
            ],
            shortTitle: "Start Workout", systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: StartRestTimerIntent(),
            phrases: [
                "Start rest in \(.applicationName)",
                "Rest timer in \(.applicationName)"
            ],
            shortTitle: "Rest Timer", systemImageName: "timer"
        )
        AppShortcut(
            intent: LogBodyweightIntent(),
            phrases: [
                "Log bodyweight in \(.applicationName)",
                "Log my weight in \(.applicationName)"
            ],
            shortTitle: "Log Bodyweight", systemImageName: "scalemass"
        )
        AppShortcut(
            intent: LastSessionIntent(),
            phrases: [
                "What did I do for \(\.$exercise) in \(.applicationName)",
                "Last \(\.$exercise) in \(.applicationName)"
            ],
            shortTitle: "Last Session", systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: ShowGymCardIntent(),
            phrases: [
                "Show my gym card in \(.applicationName)",
                "Gym card in \(.applicationName)"
            ],
            shortTitle: "Gym Card", systemImageName: "qrcode"
        )
    }
}
