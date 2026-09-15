import Foundation

/// A full, versioned export of a user's data — "your data is yours" (plan.md
/// §6.3). Pure value types only: no SwiftData, no app-side identifiers
/// beyond what's needed to round-trip through `BackupService`.
///
/// Exercises are exported two ways: full rows for custom exercises (which
/// exist nowhere else), and small override rows for seeded exercises the
/// user has personalized (favorited, or changed rest/bar/increment),
/// referenced by `seedID` so a re-import matches the built-in library
/// instead of duplicating it.
///
/// Format history: 1 was the launch shape; every section since (programs, achievements,
/// schedule, notes, photos, gym cards, coach interactions, health imports, `machine`,
/// `inclinePercent`, `restrictsMachines`…) was added as an optional field without a bump.
/// Format 2 adds `minimumReaderVersion` and `sections`, and replaces the JSON-in-JSON strings
/// (`progressionRuleJSON`, `stallJSON`, `scheduleJSON`) and the parallel plate arrays with
/// nested values; the old fields are still read.
public struct BackupDocument: VersionedDocument, Sendable {
    public static let currentFormatVersion = 2
    /// A format-2 reader is needed: format 1 rejected any newer file outright, so nothing older
    /// could read this anyway. Bump only when a field the app can't restore without is added.
    public static let minimumReaderVersion = 2

    public var formatVersion: Int
    public var minimumReaderVersion: Int?
    public var exportedAt: Date
    public var appVersion: String

    public var exercises: [BackupExercise]
    public var routines: [BackupRoutine]
    public var workouts: [BackupWorkout]
    public var bodyMeasurements: [BackupBodyMeasurement]
    public var equipmentProfiles: [BackupEquipmentProfile]
    public var preferences: BackupPreferences
    /// Added after format 1 shipped; optional so older exports still decode.
    public var programs: [BackupProgram]?
    public var achievements: [BackupAchievement]?
    public var schedule: BackupSchedule?
    /// Added after the format-1 gaps were found; all optional so older exports still decode, and
    /// so an export that deliberately leaves photos out is distinguishable from one with none.
    public var exerciseNotes: [BackupExerciseNote]?
    public var progressPhotos: [BackupProgressPhoto]?
    public var gymCards: [BackupGymCard]?
    public var coachInteractions: [BackupCoachInteraction]?
    public var healthImports: BackupHealthImport?
    /// The names of every section this file carries — the required ones plus whichever optional
    /// ones are non-nil — so a reader can tell "this file has no photos" from "this file has a
    /// section I don't know about" (`unreadableSections`). Stamped by `init` from the fields;
    /// nil in format-1 files.
    public var sections: [String]?

    public init(
        formatVersion: Int = BackupDocument.currentFormatVersion,
        minimumReaderVersion: Int? = BackupDocument.minimumReaderVersion,
        exportedAt: Date,
        appVersion: String,
        exercises: [BackupExercise] = [],
        routines: [BackupRoutine] = [],
        workouts: [BackupWorkout] = [],
        bodyMeasurements: [BackupBodyMeasurement] = [],
        equipmentProfiles: [BackupEquipmentProfile] = [],
        preferences: BackupPreferences,
        programs: [BackupProgram]? = nil,
        achievements: [BackupAchievement]? = nil,
        schedule: BackupSchedule? = nil,
        exerciseNotes: [BackupExerciseNote]? = nil,
        progressPhotos: [BackupProgressPhoto]? = nil,
        gymCards: [BackupGymCard]? = nil,
        coachInteractions: [BackupCoachInteraction]? = nil,
        healthImports: BackupHealthImport? = nil
    ) {
        self.formatVersion = formatVersion
        self.minimumReaderVersion = minimumReaderVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.exercises = exercises
        self.routines = routines
        self.workouts = workouts
        self.bodyMeasurements = bodyMeasurements
        self.equipmentProfiles = equipmentProfiles
        self.preferences = preferences
        self.programs = programs
        self.achievements = achievements
        self.schedule = schedule
        self.exerciseNotes = exerciseNotes
        self.progressPhotos = progressPhotos
        self.gymCards = gymCards
        self.coachInteractions = coachInteractions
        self.healthImports = healthImports
        sections = Self.requiredSections + presentOptionalSections
    }

    // MARK: - Sections

    /// Sections every file carries.
    public static let requiredSections = [
        "exercises", "routines", "workouts", "bodyMeasurements", "equipmentProfiles", "preferences"
    ]

    /// Sections this build knows how to read but a file may leave out.
    public static let optionalSections = [
        "programs", "achievements", "schedule", "exerciseNotes", "progressPhotos", "gymCards",
        "coachInteractions", "healthImports"
    ]

    /// The optional sections this document actually carries.
    public var presentOptionalSections: [String] {
        let present: [(String, Bool)] = [
            ("programs", programs != nil), ("achievements", achievements != nil),
            ("schedule", schedule != nil), ("exerciseNotes", exerciseNotes != nil),
            ("progressPhotos", progressPhotos != nil), ("gymCards", gymCards != nil),
            ("coachInteractions", coachInteractions != nil), ("healthImports", healthImports != nil)
        ]
        return present.filter(\.1).map(\.0)
    }

    /// Optional sections this build reads that the file doesn't carry — an older export, or one
    /// that deliberately left photos out. Nothing was lost by *this* reader; the preview can say
    /// what won't be restored.
    public var absentSections: [String] {
        let present = Set(presentOptionalSections)
        return Self.optionalSections.filter { !present.contains($0) }
    }

    /// Sections the file says it carries that this build doesn't know — a newer export restored
    /// on an older app. Those keys were dropped on decode; this is the list the user should see.
    /// Empty for a format-1 file, which carries no `sections` stamp.
    public var unreadableSections: [String] {
        let known = Set(Self.requiredSections + Self.optionalSections)
        return (sections ?? []).filter { !known.contains($0) }
    }
}
