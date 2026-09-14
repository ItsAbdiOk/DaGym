import Foundation

// The tables `BackupDocument` gained after the format-1 gaps were found: exercise notes, progress
// photos, gym cards, coach interactions and the Apple Health import bookkeeping. Split out of
// `BackupDocument.swift` purely to keep that file under the length cap — these are part of the
// same document and are all optional on it, so an older export still decodes. `BackupPreferences`
// lives here too, for the same length reason.

/// Snapshot of `DaGym.Preferences`, duplicated here (rather than depending
/// on the app target) so `GymCore` stays UI/app-free. Every key the user can
/// change from a settings screen is carried, because a restore onto a new
/// phone that only brought back nine of them left the lifter back on kg, RPE,
/// 150 s rest and a Monday week start with no way to tell what was lost.
///
/// Everything after `weekStartsMonday` is optional: a backup written before
/// this type was widened has to keep decoding, and a `nil` there means "this
/// file never carried the key", which the importer leaves alone rather than
/// overwriting with a default.
public struct BackupPreferences: Codable, Sendable {
    public var weightUnit: String
    public var effortScale: String
    public var defaultRestSeconds: Int
    public var weeklyGoal: Int
    public var keepScreenAwake: Bool
    public var restSound: Bool
    public var restHaptics: Bool
    public var restScreenFlash: Bool
    public var weekStartsMonday: Bool

    public var healthWriteWorkouts: Bool?
    public var healthSyncBodyweight: Bool?
    public var healthReadRecovery: Bool?
    public var healthReadBodyComposition: Bool?
    public var healthImportWorkouts: Bool?
    public var healthAutoImportWorkouts: Bool?
    public var healthEstimateCalories: Bool?
    public var calendarSyncEnabled: Bool?
    public var scheduledStartHour: Int?
    public var iCloudSyncEnabled: Bool?
    public var streakRemindersEnabled: Bool?
    public var weeklyRecapEnabled: Bool?
    public var reminderHour: Int?
    public var bodyweightGoalKg: Double?
    public var lockPhotos: Bool?
    public var hasCompletedOnboarding: Bool?
    public var trainingGoal: String?
    public var deloadSnoozedUntil: Date?
    public var accent: String?
    public var compactWorkoutLayout: Bool?
    public var showSetSteppers: Bool?
    public var restPauseSeconds: Int?
    public var workoutDayReminderEnabled: Bool?
    public var workoutDayReminderHour: Int?
    public var effortTrackingEnabled: Bool?
    public var appearance: String?
    public var bodyFigure: String?
    public var playRestSoundOnSilent: Bool?
    public var weighInBeforeWorkout: Bool?
    public var voiceSpeakBackOnHeadphones: Bool?
    public var voiceAutoLogEnabled: Bool?
    /// `DistanceUnit` raw value ("km"/"mi").
    public var distanceUnit: String?

    public init(
        weightUnit: String = "kg", effortScale: String = "rpe", defaultRestSeconds: Int = 150,
        weeklyGoal: Int = 4, keepScreenAwake: Bool = true, restSound: Bool = true,
        restHaptics: Bool = true, restScreenFlash: Bool = false, weekStartsMonday: Bool = true
    ) {
        self.weightUnit = weightUnit
        self.effortScale = effortScale
        self.defaultRestSeconds = defaultRestSeconds
        self.weeklyGoal = weeklyGoal
        self.keepScreenAwake = keepScreenAwake
        self.restSound = restSound
        self.restHaptics = restHaptics
        self.restScreenFlash = restScreenFlash
        self.weekStartsMonday = weekStartsMonday
    }
}

/// A note the lifter left on an exercise beyond the current session
/// (`DaGym.ExerciseNoteModel`). Referenced by `exerciseSeedID`/`exerciseName`
/// so it re-attaches to the right exercise on a restore.
public struct BackupExerciseNote: Codable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseSeedID: String?
    public var exerciseName: String
    public var text: String
    public var scope: String
    public var createdAt: Date
    public var workoutID: UUID?

    public init(
        id: UUID, exerciseSeedID: String? = nil, exerciseName: String = "", text: String = "",
        scope: String = "next", createdAt: Date = Date(), workoutID: UUID? = nil
    ) {
        self.id = id
        self.exerciseSeedID = exerciseSeedID
        self.exerciseName = exerciseName
        self.text = text
        self.scope = scope
        self.createdAt = createdAt
        self.workoutID = workoutID
    }
}

/// One progress photo (`DaGym.ProgressPhotoModel`), image bytes included as
/// base64 — a photo the user can't get back isn't a backup. The full-size JPEG
/// travels; the thumbnail is regenerated on import rather than doubling the
/// file size.
public struct BackupProgressPhoto: Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var pose: String
    public var bodyweightKg: Double?
    public var notes: String
    /// Base64-encoded JPEG. Nil when the row had no image (or the export was
    /// asked to leave photos out).
    public var imageBase64: String?

    public init(
        id: UUID, date: Date, pose: String = "front", bodyweightKg: Double? = nil,
        notes: String = "", imageBase64: String? = nil
    ) {
        self.id = id
        self.date = date
        self.pose = pose
        self.bodyweightKg = bodyweightKg
        self.notes = notes
        self.imageBase64 = imageBase64
    }
}

/// A gym check-in card (`DaGym.GymCardModel`).
public struct BackupGymCard: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var value: String
    public var symbology: String
    public var sortOrder: Int
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID, name: String = "", value: String = "", symbology: String = "qr",
        sortOrder: Int = 0, createdAt: Date = Date(), lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.symbology = symbology
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

/// One persisted Approve/Dismiss of a coach card
/// (`DaGym.CoachInteractionModel`) — without it a restore forgets every
/// dismissal and the same cards come straight back.
public struct BackupCoachInteraction: Codable, Sendable, Identifiable {
    public var id: UUID
    public var rule: String
    public var fingerprint: String
    public var outcome: String
    public var date: Date

    public init(
        id: UUID, rule: String = "", fingerprint: String = "", outcome: String = "dismissed",
        date: Date = Date()
    ) {
        self.id = id
        self.rule = rule
        self.fingerprint = fingerprint
        self.outcome = outcome
        self.date = date
    }
}

/// The Apple Health import bookkeeping: sessions already imported, and
/// tombstones for ones the user deleted. Without the tombstones a restore
/// re-imports every external workout the user has ever said no to.
public struct BackupHealthImport: Codable, Sendable {
    public var imported: [BackupImportedHealthWorkout]
    public var ignoredHealthKitIDs: [String]

    public init(
        imported: [BackupImportedHealthWorkout] = [], ignoredHealthKitIDs: [String] = []
    ) {
        self.imported = imported
        self.ignoredHealthKitIDs = ignoredHealthKitIDs
    }
}

public struct BackupImportedHealthWorkout: Codable, Sendable, Identifiable {
    public var id: UUID
    public var healthKitID: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date
    public var importedAt: Date

    public init(
        id: UUID, healthKitID: String, title: String, startedAt: Date, endedAt: Date,
        importedAt: Date
    ) {
        self.id = id
        self.healthKitID = healthKitID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.importedAt = importedAt
    }
}
