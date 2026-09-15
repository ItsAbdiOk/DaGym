import Foundation
import GymCore
import SwiftData

/// Counts and problems from `BackupService.import`, shown in the Settings
/// import preview sheet before the user confirms.
struct ImportReport: Equatable {
    var exercisesImported = 0
    var routinesImported = 0
    var workoutsImported = 0
    var workoutsSkipped = 0
    var bodyMeasurementsImported = 0
    var equipmentProfilesImported = 0
    var exerciseNotesImported = 0
    var photosImported = 0
    var healthTombstonesImported = 0
    /// Set by `import` once the file's settings have been written back onto `Preferences`.
    var preferencesRestored = false
    var problems: [String] = []

    /// "12 workouts, 3 routines, 2 custom exercises · 1 problem" for the preview sheet — and for
    /// the confirmation footnote, which used to say a flat "Imported" and so never told the user
    /// that hundreds of rows had been skipped.
    var summary: String {
        let parts = [
            countPhrase(workoutsImported, singular: "workout"),
            countPhrase(routinesImported, singular: "routine"),
            countPhrase(exercisesImported, singular: "custom exercise"),
            countPhrase(photosImported, singular: "photo")
        ].compactMap { $0 }
        var text = parts.isEmpty ? "Nothing new to import" : parts.joined(separator: ", ")
        if workoutsSkipped > 0 {
            text += " · \(workoutsSkipped) already here"
        }
        if !problems.isEmpty {
            text += " · \(countPhrase(problems.count, singular: "problem") ?? "")"
        }
        return text
    }

    private func countPhrase(_ count: Int, singular: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

enum ImportMode {
    /// The only supported mode: never overwrites existing rows.
    case merge
}

/// Exports the live store to a `BackupDocument` and imports one back in,
/// merging — matched rows are never overwritten, and importing the same
/// file twice produces no duplicates (plan.md §6.3, §6.8).
@MainActor
enum BackupService {
    /// What a seeded exercise looked like before the user touched it. A seeded row is exported
    /// (and, on import, applied) as an override only where it differs from this, so a backup
    /// carries the user's edits and nothing else. Falls back to the library defaults for a
    /// `seedID` the bundled seed no longer knows. Rest is never taken from the seed: a seeded
    /// row's unedited rest is 0 ("use Settings → Default rest"), so any non-zero value is an
    /// override — except the seed's own number, which is what every backup written before seed
    /// v4 carries for an unedited row (`legacyRestSeconds`).
    struct SeedBaseline {
        struct Values {
            /// The seed item's `restSeconds`: the value an unedited seeded row held before seed
            /// v4 moved unedited rest to 0, and so the value a pre-v4 backup or a pre-v4 device's
            /// copy carries for a row the lifter never touched.
            var legacyRestSeconds: Int
            var incrementKg: Double
            var barType: String?
            var machine: String?
        }

        private let bySeedID: [String: Values]
        private let fallback = Values(legacyRestSeconds: 0, incrementKg: 2.5, barType: nil, machine: nil)

        init(bundle: Bundle = .main) {
            let seed = try? ExerciseSeeder.loadSeed(bundle: bundle)
            bySeedID = Dictionary(
                (seed?.exercises ?? []).map { item in
                    let values = Values(
                        legacyRestSeconds: item.restSeconds, incrementKg: item.incrementKg, barType: item.bar,
                        machine: item.machine
                    )
                    return (item.id, values)
                },
                uniquingKeysWith: { first, _ in first }
            )
        }

        /// Whether `restSeconds` on a seeded row is a real per-exercise override: not 0 ("use
        /// the default") and not the seed's own number, which is unedited rest as a pre-v4
        /// export or device wrote it. Restoring last week's backup used to turn every
        /// favourited seeded lift's 90/120 s into a permanent override that Settings → Default
        /// rest no longer reached.
        func isRestOverride(_ restSeconds: Int, seedID: String?) -> Bool {
            restSeconds != 0 && restSeconds != values(for: seedID).legacyRestSeconds
        }

        func values(for seedID: String?) -> Values {
            seedID.flatMap { bySeedID[$0] } ?? fallback
        }

        func isOverridden(_ model: ExerciseModel) -> Bool {
            let seeded = values(for: model.seedID)
            return model.isFavorite || !model.notes.isEmpty || model.restSeconds != 0
                || model.incrementKg != seeded.incrementKg || model.barType != seeded.barType
                || model.machine != seeded.machine
        }
    }

    // MARK: - Export

    /// The document only — the common case. `exportResult` (see `BackupService+Export.swift`)
    /// also reports anything the export couldn't carry faithfully.
    static func export(
        context: ModelContext, baseline: SeedBaseline = SeedBaseline(),
        photoContext: ModelContext? = nil, healthContext: ModelContext? = nil,
        preferences: Preferences? = nil
    ) -> BackupDocument {
        exportResult(
            context: context, baseline: baseline, photoContext: photoContext,
            healthContext: healthContext, preferences: preferences
        ).document
    }

    /// Every settings key a restore is expected to bring back. Kept in one place with
    /// `applyPreferences` (`BackupService+ImportPreferences.swift`) so a key added to
    /// `Preferences` and to one of the two shows up as a compile-visible asymmetry here rather
    /// than as a silently-lost setting on the user's new phone.
    ///
    /// One deliberate omission: `sampleDataMode` is a transient "this store is full of demo data"
    /// flag, not a setting the lifter chose, and restoring it onto a real store would put a wipe
    /// banner over their own data.
    static func exportPreferences(_ preferences: Preferences) -> BackupPreferences {
        var backup = BackupPreferences(
            weightUnit: preferences.weightUnit.rawValue, effortScale: preferences.effortScale.rawValue,
            defaultRestSeconds: preferences.defaultRestSeconds, weeklyGoal: preferences.weeklyGoal,
            keepScreenAwake: preferences.keepScreenAwake, restSound: preferences.restSound,
            restHaptics: preferences.restHaptics, restScreenFlash: preferences.restScreenFlash,
            weekStartsMonday: preferences.weekStartsMonday
        )
        backup.healthWriteWorkouts = preferences.healthWriteWorkouts
        backup.healthSyncBodyweight = preferences.healthSyncBodyweight
        backup.healthReadRecovery = preferences.healthReadRecovery
        backup.healthReadBodyComposition = preferences.healthReadBodyComposition
        backup.healthImportWorkouts = preferences.healthImportWorkouts
        backup.healthAutoImportWorkouts = preferences.healthAutoImportWorkouts
        backup.healthEstimateCalories = preferences.healthEstimateCalories
        backup.calendarSyncEnabled = preferences.calendarSyncEnabled
        backup.scheduledStartHour = preferences.scheduledStartHour
        backup.iCloudSyncEnabled = preferences.iCloudSyncEnabled
        backup.streakRemindersEnabled = preferences.streakRemindersEnabled
        backup.weeklyRecapEnabled = preferences.weeklyRecapEnabled
        backup.reminderHour = preferences.reminderHour
        backup.bodyweightGoalKg = preferences.bodyweightGoalKg
        backup.lockPhotos = preferences.lockPhotos
        backup.hasCompletedOnboarding = preferences.hasCompletedOnboarding
        backup.trainingGoal = preferences.trainingGoal.rawValue
        backup.deloadSnoozedUntil = preferences.deloadSnoozedUntil
        backup.accent = preferences.accent.rawValue
        backup.compactWorkoutLayout = preferences.compactWorkoutLayout
        backup.showSetSteppers = preferences.showSetSteppers
        backup.restPauseSeconds = preferences.restPauseSeconds
        backup.workoutDayReminderEnabled = preferences.workoutDayReminderEnabled
        backup.workoutDayReminderHour = preferences.workoutDayReminderHour
        backup.effortTrackingEnabled = preferences.effortTrackingEnabled
        backup.appearance = preferences.appearance.rawValue
        backup.bodyFigure = preferences.bodyFigure.rawValue
        backup.playRestSoundOnSilent = preferences.playRestSoundOnSilent
        backup.weighInBeforeWorkout = preferences.weighInBeforeWorkout
        backup.voiceSpeakBackOnHeadphones = preferences.voiceSpeakBackOnHeadphones
        backup.voiceAutoLogEnabled = preferences.voiceAutoLogEnabled
        backup.coachModelID = preferences.coachModelID
        backup.coachChatConsentGiven = preferences.coachChatConsentGiven
        backup.distanceUnit = preferences.distanceUnit.rawValue
        return backup
    }

    static func currentAppVersion() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

}
