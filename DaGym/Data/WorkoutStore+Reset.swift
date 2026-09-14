import Foundation
import SwiftData

extension WorkoutStore {
    /// Deletes every persisted model — routines, workouts, exercises, schedule, equipment
    /// profiles, achievements, programs, progress photos, imported Apple Health sessions,
    /// everything in `DaGymSchema.models` —
    /// and resets `preferences` back to its shipped defaults. Used by the Settings "Reset
    /// everything" destructive row, which only calls this after a typed "DELETE" confirmation.
    func wipeAllData(preferences: Preferences) {
        deleteAllMainModels()
        save()
        if let photoContext {
            try? photoContext.delete(model: ProgressPhotoModel.self, includeSubclasses: true)
            savePhotos()
        }
        if let healthContext {
            try? healthContext.delete(model: ImportedHealthWorkoutModel.self, includeSubclasses: true)
            try? healthContext.delete(model: IgnoredHealthWorkoutModel.self, includeSubclasses: true)
            saveHealth()
        }
        Self.resetToDefaults(preferences)
    }

    /// One `ModelContext.delete(model:)` batch delete per main-store type. Written out
    /// explicitly (rather than looping `DaGymSchema.mainModels`) so this stays a plain generic
    /// call on a concrete type — `FeatureSettingsTests` asserts the count matches
    /// `DaGymSchema.mainModels` so a model added to the schema without a line here fails loudly.
    private func deleteAllMainModels() {
        try? context.delete(model: ExerciseModel.self, includeSubclasses: true)
        try? context.delete(model: RoutineModel.self, includeSubclasses: true)
        try? context.delete(model: RoutineExerciseModel.self, includeSubclasses: true)
        try? context.delete(model: PlannedSetModel.self, includeSubclasses: true)
        try? context.delete(model: WorkoutModel.self, includeSubclasses: true)
        try? context.delete(model: WorkoutExerciseModel.self, includeSubclasses: true)
        try? context.delete(model: SetLogModel.self, includeSubclasses: true)
        try? context.delete(model: BodyMeasurementModel.self, includeSubclasses: true)
        try? context.delete(model: PersonalRecordModel.self, includeSubclasses: true)
        try? context.delete(model: PersonalRecordEventModel.self, includeSubclasses: true)
        try? context.delete(model: EquipmentProfileModel.self, includeSubclasses: true)
        try? context.delete(model: ScheduleModel.self, includeSubclasses: true)
        try? context.delete(model: AchievementModel.self, includeSubclasses: true)
        try? context.delete(model: ProgramModel.self, includeSubclasses: true)
        try? context.delete(model: ProgramWeekModel.self, includeSubclasses: true)
        try? context.delete(model: SeedStateModel.self, includeSubclasses: true)
        try? context.delete(model: ExerciseNoteModel.self, includeSubclasses: true)
        try? context.delete(model: GymCardModel.self, includeSubclasses: true)
        try? context.delete(model: CoachInteractionModel.self, includeSubclasses: true)
    }

    /// Every `Preferences` property, written back to the same default each `init(suite:)` uses.
    /// Listed explicitly (rather than a `Preferences.resetToDefaults()` method) since
    /// `DaGym/Design/UnitEnvironment.swift` isn't part of this change.
    private static func resetToDefaults(_ preferences: Preferences) {
        preferences.weightUnit = .kg
        preferences.effortScale = .rpe
        preferences.defaultRestSeconds = 150
        preferences.weeklyGoal = 4
        preferences.keepScreenAwake = true
        preferences.restSound = true
        preferences.restHaptics = true
        preferences.restScreenFlash = false
        preferences.weekStartsMonday = true
        preferences.healthWriteWorkouts = false
        preferences.healthSyncBodyweight = false
        preferences.healthReadRecovery = false
        preferences.healthReadBodyComposition = false
        preferences.healthImportWorkouts = false
        preferences.healthAutoImportWorkouts = false
        preferences.healthEstimateCalories = false
        preferences.calendarSyncEnabled = false
        preferences.scheduledStartHour = 18
        preferences.iCloudSyncEnabled = true
        preferences.streakRemindersEnabled = false
        preferences.weeklyRecapEnabled = false
        preferences.reminderHour = 18
        preferences.bodyweightGoalKg = nil
        preferences.syncPhotos = false
        preferences.lockPhotos = false
        preferences.hasCompletedOnboarding = false
        preferences.trainingGoal = ""
        preferences.deloadSnoozedUntil = nil
        preferences.deloadDismissedFingerprint = nil
        preferences.accent = .coral
        preferences.compactWorkoutLayout = false
        preferences.showSetSteppers = false
        preferences.restPauseSeconds = 20
        preferences.workoutDayReminderEnabled = false
        preferences.workoutDayReminderHour = 8
        preferences.effortTrackingEnabled = true
        preferences.appearance = .system
        preferences.bodyFigure = .neutral
        preferences.playRestSoundOnSilent = false
        preferences.weighInBeforeWorkout = false
        preferences.sampleDataMode = false
    }
}
