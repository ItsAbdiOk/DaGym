import AppIntents
import GymCore

/// "Log bodyweight" Siri Shortcut / App Intent (voice-logging-plan.md §6.1 `LogBodyweightIntent`,
/// plan.md §6.8). Runs entirely without opening the app (`openAppWhenRun = false`) — unlike
/// `StartWorkoutIntent` it never touches a live `WorkoutStore`, opening its own short-lived one
/// via `IntentStoreAccess` instead, which is also what keeps it a no-op under
/// `LaunchFlags.isTesting`.
struct LogBodyweightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Bodyweight"
    static let openAppWhenRun = false

    /// Always in the user's preferred unit (`Preferences.weightUnit`) — converted to canonical kg
    /// before it's stored, same as every other weight entry point in the app.
    @Parameter(title: "Weight")
    var weight: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Log bodyweight of \(\.$weight)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = IntentStoreAccess.makeStore() else {
            return .result(dialog: IntentDialog(stringLiteral: "DaGym isn't available right now."))
        }
        let preferences = Preferences()
        let unit = preferences.weightUnit
        let kg = unit.toKg(weight)
        // The pushed Health sample carries the logged row's own date, so the two sides describe
        // the same weigh-in rather than two a few milliseconds apart.
        let logged = store.logBodyweight(kg: kg)
        let health = HealthSyncService(workoutStore: store, preferences: preferences)
        await health.pushBodyweight(kg: kg, date: logged.date)
        let dialog = IntentFormatting.bodyweightLoggedDialog(kg: kg, unit: unit)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
