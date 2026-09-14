import Foundation
import GymCore
import SwiftData

extension BackupService {
    /// Writes a backup's settings back onto `preferences`.
    ///
    /// Export has always carried `preferences`; nothing ever read them back, so restoring onto a
    /// new phone left the lifter on kg, RPE, 150 s rest and a Monday week start no matter what
    /// they had chosen. This is the missing half.
    ///
    /// Unlike the rest of the import, this *does* overwrite — the user picked this file and asked
    /// for their settings back, and a merge has no meaning for a scalar preference. Two
    /// deliberate exceptions: a key the file never carried (an older export, `nil` here) is left
    /// alone rather than reset to a default, and `hasCompletedOnboarding` only ever moves
    /// forwards, so restoring an old backup can't drop a set-up device back into onboarding.
    static func applyPreferences(_ backup: BackupPreferences, to preferences: Preferences) {
        applyCore(backup, to: preferences)
        applyHealth(backup, to: preferences)
        applyNotifications(backup, to: preferences)
        applyDisplay(backup, to: preferences)
    }

    private static func applyCore(_ backup: BackupPreferences, to preferences: Preferences) {
        if let unit = WeightUnit(rawValue: backup.weightUnit) { preferences.weightUnit = unit }
        if let scale = Effort.Scale(rawValue: backup.effortScale) { preferences.effortScale = scale }
        preferences.defaultRestSeconds = backup.defaultRestSeconds
        preferences.weeklyGoal = backup.weeklyGoal
        preferences.keepScreenAwake = backup.keepScreenAwake
        preferences.restSound = backup.restSound
        preferences.restHaptics = backup.restHaptics
        preferences.restScreenFlash = backup.restScreenFlash
        preferences.weekStartsMonday = backup.weekStartsMonday
        if let value = backup.restPauseSeconds { preferences.restPauseSeconds = value }
        if let value = backup.effortTrackingEnabled { preferences.effortTrackingEnabled = value }
        if let value = backup.weighInBeforeWorkout { preferences.weighInBeforeWorkout = value }
        if let value = backup.playRestSoundOnSilent { preferences.playRestSoundOnSilent = value }
        if let value = backup.iCloudSyncEnabled { preferences.iCloudSyncEnabled = value }
        if let raw = backup.trainingGoal, let goal = Preferences.TrainingGoal(rawValue: raw) {
            preferences.trainingGoal = goal
        }
        if backup.hasCompletedOnboarding == true { preferences.hasCompletedOnboarding = true }
    }

    private static func applyHealth(_ backup: BackupPreferences, to preferences: Preferences) {
        if let value = backup.healthWriteWorkouts { preferences.healthWriteWorkouts = value }
        if let value = backup.healthSyncBodyweight { preferences.healthSyncBodyweight = value }
        if let value = backup.healthReadRecovery { preferences.healthReadRecovery = value }
        if let value = backup.healthReadBodyComposition {
            preferences.healthReadBodyComposition = value
        }
        if let value = backup.healthImportWorkouts { preferences.healthImportWorkouts = value }
        if let value = backup.healthAutoImportWorkouts {
            preferences.healthAutoImportWorkouts = value
        }
        if let value = backup.healthEstimateCalories { preferences.healthEstimateCalories = value }
        if let value = backup.bodyweightGoalKg { preferences.bodyweightGoalKg = value }
        if let value = backup.lockPhotos { preferences.lockPhotos = value }
    }

    private static func applyNotifications(_ backup: BackupPreferences, to preferences: Preferences) {
        if let value = backup.calendarSyncEnabled { preferences.calendarSyncEnabled = value }
        if let value = backup.scheduledStartHour { preferences.scheduledStartHour = value }
        if let value = backup.streakRemindersEnabled { preferences.streakRemindersEnabled = value }
        if let value = backup.weeklyRecapEnabled { preferences.weeklyRecapEnabled = value }
        if let value = backup.reminderHour { preferences.reminderHour = value }
        if let value = backup.workoutDayReminderEnabled {
            preferences.workoutDayReminderEnabled = value
        }
        if let value = backup.workoutDayReminderHour { preferences.workoutDayReminderHour = value }
    }

    private static func applyDisplay(_ backup: BackupPreferences, to preferences: Preferences) {
        if let raw = backup.accent, let accent = DGAccent(rawValue: raw) { preferences.accent = accent }
        if let raw = backup.appearance, let value = Preferences.Appearance(rawValue: raw) {
            preferences.appearance = value
        }
        if let raw = backup.bodyFigure, let value = Preferences.BodyFigure(rawValue: raw) {
            preferences.bodyFigure = value
        }
        if let value = backup.compactWorkoutLayout { preferences.compactWorkoutLayout = value }
        if let value = backup.showSetSteppers { preferences.showSetSteppers = value }
        if let value = backup.deloadSnoozedUntil { preferences.deloadSnoozedUntil = value }
        if let value = backup.voiceSpeakBackOnHeadphones {
            preferences.voiceSpeakBackOnHeadphones = value
        }
        if let value = backup.voiceAutoLogEnabled { preferences.voiceAutoLogEnabled = value }
        if let unit = backup.distanceUnit.flatMap(DistanceUnit.init(rawValue:)) {
            preferences.distanceUnit = unit
        }
    }
}
