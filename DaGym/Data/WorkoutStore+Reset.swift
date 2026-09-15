import Foundation
import SwiftData
import UserNotifications

/// The non-SwiftData things "Reset everything" also has to clear, injected so tests can run a
/// full wipe without touching the developer's real notification centre, calendar, widget or
/// Keychain. `.live` is what the app uses.
@MainActor
struct ResetSideEffects {
    // `@MainActor` on each closure type, not just on the struct: a closure formed inside a
    // `@MainActor` member is main-actor-isolated, and Swift 6 refuses to drop that isolation
    // when storing it in a plain `() -> Void`.
    var cancelNotifications: @MainActor () -> Void
    var clearWidgetSnapshot: @MainActor () -> Void
    var removeSecrets: @MainActor () -> Void
    var deleteCalendarEvents: @MainActor ([String]) -> Void

    /// Inert in a test process, like `WidgetSnapshotWriter.live`: unit tests must not clear the
    /// developer's real notifications, calendar events, widget snapshot or Keychain.
    static var live: ResetSideEffects {
        guard !LaunchFlags.isTesting else { return .inert }
        return ResetSideEffects(
            cancelNotifications: {
                let center = UNUserNotificationCenter.current()
                center.removeAllPendingNotificationRequests()
                center.removeAllDeliveredNotifications()
            },
            clearWidgetSnapshot: {
                guard let suite = WidgetSnapshotStore.appGroupSuite else { return }
                WidgetSnapshotStore.write(.empty, to: suite)
            },
            removeSecrets: { KeychainStore.remove(account: HevyAPIClient.keychainAccount) },
            deleteCalendarEvents: { ids in
                guard !ids.isEmpty else { return }
                let store = EventKitStore()
                for id in ids { try? store.deleteEvent(id: id) }
            }
        )
    }

    /// Does nothing — the default for tests and previews.
    static var inert: ResetSideEffects {
        ResetSideEffects(
            cancelNotifications: {}, clearWidgetSnapshot: {}, removeSecrets: {},
            deleteCalendarEvents: { _ in }
        )
    }
}

extension WorkoutStore {
    /// Deletes every persisted model — routines, workouts, exercises, schedule, equipment
    /// profiles, achievements, programs, progress photos, imported Apple Health sessions,
    /// everything in `DaGymSchema.models` — clears everything the app left *outside* the store
    /// (pending notifications, the App Group widget snapshot, the calendar events the schedule
    /// sync created, the Hevy Keychain key), resets `preferences` back to its shipped defaults,
    /// and re-seeds the library so the user lands on a fresh install rather than an empty app.
    /// Used by the Settings "Reset everything" destructive row, which only calls this after a
    /// typed "DELETE" confirmation.
    func wipeAllData(preferences: Preferences, effects: ResetSideEffects = .live) {
        effects.cancelNotifications()
        // Read *before* the schedule rows go: these ids are the only handle on the events the
        // calendar sync created, so deleting the rows first orphaned every event forever.
        effects.deleteCalendarEvents(Array(scheduleEventIDs().values))
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
        effects.clearWidgetSnapshot()
        effects.removeSecrets()
        reseedAfterWipe()
    }

    /// Re-runs the first-launch seeders so the user gets the exercise library, starter routines
    /// and equipment profiles straight back. Without this the app sat completely empty until
    /// the next cold launch, which reads as "the reset broke it".
    private func reseedAfterWipe() {
        ExerciseSeeder.seedIfNeeded(context: context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: self)
        EquipmentSeeder.seedIfNeeded(store: self)
        save()
    }

    /// Deletes every row of every main-store type, **one object at a time**.
    ///
    /// This used to be `ModelContext.delete(model:)` per type, which issues an
    /// `NSBatchDeleteRequest`. `NSPersistentCloudKitContainer` does not export batch operations
    /// — it mirrors changes it sees in the persistent history as object-level changes — so with
    /// iCloud sync on, a "reset everything" deleted nothing in CloudKit and every row imported
    /// straight back minutes later, from the cloud and from the user's other device.
    private func deleteAllMainModels() {
        for erase in Self.mainModelErasers { erase(context) }
    }

    /// One eraser per main-store type. `FeatureSettingsTests` asserts this list covers
    /// `DaGymSchema.mainModels`, so a model added to the schema without a line here fails loudly.
    static let mainModelErasers: [@MainActor (ModelContext) -> Void] = [
        eraser(ExerciseModel.self),
        eraser(RoutineModel.self),
        eraser(RoutineExerciseModel.self),
        eraser(PlannedSetModel.self),
        eraser(WorkoutModel.self),
        eraser(WorkoutExerciseModel.self),
        eraser(SetLogModel.self),
        eraser(BodyMeasurementModel.self),
        eraser(PersonalRecordModel.self),
        eraser(PersonalRecordEventModel.self),
        eraser(EquipmentProfileModel.self),
        eraser(ScheduleModel.self),
        eraser(AchievementModel.self),
        eraser(ProgramModel.self),
        eraser(ProgramWeekModel.self),
        eraser(SeedStateModel.self),
        eraser(ExerciseNoteModel.self),
        eraser(GymCardModel.self),
        eraser(CoachInteractionModel.self)
    ]

    /// Per row on purpose — see `deleteAllMainModels`: a batch `delete(model:)` never reaches
    /// CloudKit. The photo and Health stores are local-only, which is why *they* may batch. A
    /// fetch failure is logged rather than swallowed: a wipe that left rows behind must not read
    /// as a clean reset.
    private static func eraser<Model: PersistentModel>(
        _ type: Model.Type
    ) -> @MainActor (ModelContext) -> Void {
        { context in
            do {
                for model in try context.fetch(FetchDescriptor<Model>()) {
                    context.delete(model)
                }
            } catch {
                let name = String(describing: Model.self)
                let reason = error.localizedDescription
                storeLogger.error("Wipe of \(name, privacy: .public) failed: \(reason, privacy: .public)")
            }
        }
    }

    /// Every `Preferences` property, written back to the same default each `init(suite:)` uses.
    /// Listed explicitly (rather than a `Preferences.resetToDefaults()` method) so a preference
    /// nobody adds a line for here fails `resetRestoresEveryPreference` instead of surviving a
    /// "Reset everything".
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
        preferences.lockPhotos = false
        preferences.hasCompletedOnboarding = false
        preferences.trainingGoal = .general
        preferences.deloadSnoozedUntil = nil
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
        preferences.voiceSpeakBackOnHeadphones = true
        preferences.voiceAutoLogEnabled = false
    }
}
