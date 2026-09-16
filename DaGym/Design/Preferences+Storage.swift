import Foundation
import GymCore
import SwiftUI

/// `UserDefaults` key names and the small typed-read helpers `Preferences.init` uses to pull each
/// stored value back out with its default — split out from `UnitEnvironment.swift` to stay under
/// the type-body-length cap.
extension Preferences {
    enum Key {
        static let weightUnit = "weightUnit"
        static let distanceUnit = "distanceUnit"
        static let effortScale = "effortScale"
        static let defaultRestSeconds = "defaultRestSeconds"
        static let weeklyGoal = "weeklyGoal"
        static let keepScreenAwake = "keepScreenAwake"
        static let restSound = "restSound"
        static let restHaptics = "restHaptics"
        static let restScreenFlash = "restScreenFlash"
        static let weekStartsMonday = "weekStartsMonday"
        static let healthWriteWorkouts = "healthWriteWorkouts"
        static let healthSyncBodyweight = "healthSyncBodyweight"
        static let healthReadRecovery = "healthReadRecovery"
        static let healthReadBodyComposition = "healthReadBodyComposition"
        static let healthImportWorkouts = "healthImportWorkouts"
        static let healthAutoImportWorkouts = "healthAutoImportWorkouts"
        static let healthEstimateCalories = "healthEstimateCalories"
        static let calendarSyncEnabled = "calendarSyncEnabled"
        static let scheduledStartHour = "scheduledStartHour"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let streakRemindersEnabled = "streakRemindersEnabled"
        static let weeklyRecapEnabled = "weeklyRecapEnabled"
        static let reminderHour = "reminderHour"
        static let bodyweightGoalKg = "bodyweightGoalKg"
        static let lockPhotos = "lockPhotos"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let trainingGoal = "trainingGoal"
        static let deloadSnoozedUntil = "deloadSnoozedUntil"
        static let accent = "accent"
        static let colorBlindHeatmaps = "colorBlindHeatmaps"
        /// The pre-three-way "Compact layout" toggle, read only to migrate into `workoutLayout`.
        static let compactWorkoutLayout = "compactWorkoutLayout"
        static let workoutLayout = "workoutLayout"
        static let showSetSteppers = "showSetSteppers"
        static let restPauseSeconds = "restPauseSeconds"
        static let workoutDayReminderEnabled = "workoutDayReminderEnabled"
        static let workoutDayReminderHour = "workoutDayReminderHour"
        static let effortTrackingEnabled = "effortTrackingEnabled"
        static let appearance = "appearance"
        static let bodyFigure = "bodyFigure"
        static let playRestSoundOnSilent = "playRestSoundOnSilent"
        static let weighInBeforeWorkout = "weighInBeforeWorkout"
        static let sampleDataMode = "sampleDataMode"
        static let starterRoutinesPruned = "starterRoutinesPruned"
        static let voiceSpeakBackOnHeadphones = "voiceSpeakBackOnHeadphones"
        static let voiceAutoLogEnabled = "voiceAutoLogEnabled"
        static let onDeviceCoachEnabled = "onDeviceCoachEnabled"
        static let coachModelID = "coachModelID"
        static let coachReviewerModelID = "coachReviewerModelID"
        static let coachChatConsentGiven = "coachChatConsentGiven"
        static let coachWeekReviewLastKey = "coachWeekReviewLastKey"
        static let coachWeekReviewDismissedKey = "coachWeekReviewDismissedKey"
    }

    enum Appearance: String, CaseIterable, Codable {
        case system, light, dark
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum BodyFigure: String, CaseIterable, Codable {
        case neutral, male, female
    }

    /// `RoutineSeeder.pruneUntouchedStartersOnce` has run on this device: the 13 starters every
    /// install used to seed were deleted where the lifter never ran, scheduled, programmed or
    /// renamed them. Per device (not a synced SwiftData field — the CloudKit schema is deployed),
    /// and read straight from the suite: it's a launch-time marker no view observes.
    var starterRoutinesPruned: Bool {
        get { Self.boolValue(defaults, Key.starterRoutinesPruned, default: false) }
        set { defaults.set(newValue, forKey: Key.starterRoutinesPruned) }
    }

    static func intValue(_ suite: UserDefaults, _ key: String, default value: Int) -> Int {
        suite.object(forKey: key) as? Int ?? value
    }

    static func boolValue(_ suite: UserDefaults, _ key: String, default value: Bool) -> Bool {
        suite.object(forKey: key) as? Bool ?? value
    }

    /// The saved layout, or the pre-three-way "Compact layout" toggle migrated when there is none.
    static func workoutLayoutValue(_ suite: UserDefaults) -> WorkoutLayout {
        WorkoutLayout(
            stored: suite.string(forKey: Key.workoutLayout),
            legacyCompact: boolValue(suite, Key.compactWorkoutLayout, default: false)
        )
    }

    /// The stored second-opinion model: nil (never set) means the default, "" means off.
    static func reviewerModelID(_ stored: String?) -> String? {
        guard let stored else { return CoachChatConfiguration.defaultReviewerModelID }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The answer to onboarding's "What's your main goal?". It is not decoration: picking one
    /// applies that goal's training defaults (`defaultRestSeconds`, `weeklyGoal`) right then, and
    /// Settings' "Goal" row re-applies them when it changes — which is exactly what each option's
    /// subtitle promises ("longer rest", "more volume").
    enum TrainingGoal: String, CaseIterable, Codable, Sendable {
        case strength
        case muscle
        case general

        var title: String {
            switch self {
            case .strength: "Strength"
            case .muscle: "Muscle"
            case .general: "General fitness"
            }
        }

        var detail: String {
            switch self {
            case .strength: "Heavier lifts, lower reps, longer rest."
            case .muscle: "More volume, moderate reps, shorter rest."
            case .general: "A balanced mix, no specific peak."
            }
        }

        /// Rest between sets this goal implies, used as the app-wide fallback rest.
        var defaultRestSeconds: Int {
            switch self {
            case .strength: 210
            case .muscle: 90
            case .general: 150
            }
        }

        /// Sessions per week this goal implies.
        var weeklyGoal: Int {
            switch self {
            case .strength: 4
            case .muscle: 5
            case .general: 3
            }
        }
    }
}
