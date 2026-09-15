import AppIntents
import GymCore

/// "What's my streak" Siri Shortcut / App Intent (plan.md §6.8). Read-only and answered in the
/// background (`openAppWhenRun = false`) through the shared store `IntentStoreAccess` hands out,
/// with the same `Streaks.weekly` maths as Home's streak tile and the widgets — so Siri, the Lock
/// Screen and the app can never quote three different numbers.
struct GetStreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Streak"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        guard let store = IntentStoreAccess.makeStore() else {
            return .result(value: 0, dialog: IntentDialog(stringLiteral: "DaGym isn't available right now."))
        }
        let streak = Self.streak(store: store, preferences: IntentStoreAccess.preferences())
        let dialog = IntentFormatting.streakDialog(
            current: streak.current, thisWeekCount: streak.thisWeekCount, weeklyGoal: streak.weeklyGoal
        )
        return .result(value: streak.current, dialog: IntentDialog(stringLiteral: dialog))
    }

    struct Streak: Equatable {
        var current: Int
        var thisWeekCount: Int
        var weeklyGoal: Int
    }

    /// Home's numbers: every finished workout's date through `Streaks.weekly` with the user's
    /// own goal and week start.
    @MainActor
    static func streak(store: WorkoutStore, preferences: Preferences, now: Date = Date()) -> Streak {
        let weekly = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: preferences.weeklyGoal,
            calendar: preferences.trainingCalendar, now: now
        )
        return Streak(
            current: weekly.current, thisWeekCount: weekly.thisWeekCount, weeklyGoal: preferences.weeklyGoal
        )
    }
}
