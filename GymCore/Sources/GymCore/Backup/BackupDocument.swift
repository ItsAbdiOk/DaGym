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
public struct BackupDocument: Codable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
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

    public init(
        formatVersion: Int = BackupDocument.currentFormatVersion,
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
    }
}

/// A custom exercise, or an override (favourite/settings) for a seeded one.
public struct BackupExercise: Codable, Sendable, Identifiable {
    public var id: UUID
    /// Non-nil for a seeded exercise override; nil for a fully custom exercise.
    public var seedID: String?
    public var name: String
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var equipment: String
    public var mechanic: String?
    public var loggingStyle: String
    public var isPerSide: Bool
    public var isCustom: Bool
    public var isFavorite: Bool
    public var barType: String?
    public var incrementKg: Double
    public var restSeconds: Int
    public var instructions: String
    public var notes: String
    public var createdAt: Date

    public init(
        id: UUID, seedID: String? = nil, name: String, primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [], equipment: String = "other", mechanic: String? = nil,
        loggingStyle: String = "weightReps", isPerSide: Bool = false, isCustom: Bool = false,
        isFavorite: Bool = false, barType: String? = nil, incrementKg: Double = 2.5,
        restSeconds: Int = 150, instructions: String = "", notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.seedID = seedID
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.mechanic = mechanic
        self.loggingStyle = loggingStyle
        self.isPerSide = isPerSide
        self.isCustom = isCustom
        self.isFavorite = isFavorite
        self.barType = barType
        self.incrementKg = incrementKg
        self.restSeconds = restSeconds
        self.instructions = instructions
        self.notes = notes
        self.createdAt = createdAt
    }
}

public struct BackupPlannedSet: Codable, Sendable {
    public var order: Int
    public var kind: String
    public var targetReps: Int?
    public var targetRepsHigh: Int?
    public var targetWeightKg: Double?
    public var targetRPE: Double?
    public var targetSeconds: Int?

    public init(
        order: Int, kind: String, targetReps: Int? = nil, targetRepsHigh: Int? = nil,
        targetWeightKg: Double? = nil, targetRPE: Double? = nil, targetSeconds: Int? = nil
    ) {
        self.order = order
        self.kind = kind
        self.targetReps = targetReps
        self.targetRepsHigh = targetRepsHigh
        self.targetWeightKg = targetWeightKg
        self.targetRPE = targetRPE
        self.targetSeconds = targetSeconds
    }
}

/// One exercise slot inside a `BackupRoutine`. Resolved back to an exercise
/// on import by `exerciseSeedID` first, then by `exerciseName`
/// (plan §6.8: "importing merges, never overwrites").
public struct BackupRoutineExercise: Codable, Sendable {
    public var order: Int
    public var exerciseSeedID: String?
    public var exerciseName: String
    public var supersetGroup: Int?
    public var restOverrideSeconds: Int?
    public var note: String
    /// Opaque JSON for a `GymCore.ProgressionRule` override on this exercise; nil defers to the
    /// routine's rule. Mirrors `DaGym.RoutineExerciseModel.progressionRuleJSON`.
    public var progressionRuleJSON: String?
    /// Opaque JSON for the engine's per-exercise memory (`GymCore.StallState`), so a restore
    /// doesn't reset stall/deload counters; nil (never persisted, or an export from before this
    /// field existed) means "no memory yet", the same as `DaGym.RoutineExerciseModel.stallJSON`'s
    /// `"{}"` default. Optional (rather than defaulting to `"{}"` outright) so decoding a backup
    /// exported before this field existed doesn't fail on a missing key.
    public var stallJSON: String?
    /// The rolling training max for `.percentOfTrainingMax`, nil until first set. Mirrors
    /// `DaGym.RoutineExerciseModel.trainingMaxKg`.
    public var trainingMaxKg: Double?
    /// Planned-deload flag on the slot; nil (older export) means false.
    public var excludeFromProgression: Bool?
    public var plannedSets: [BackupPlannedSet]

    public init(
        order: Int, exerciseSeedID: String? = nil, exerciseName: String, supersetGroup: Int? = nil,
        restOverrideSeconds: Int? = nil, note: String = "", progressionRuleJSON: String? = nil,
        stallJSON: String? = nil, trainingMaxKg: Double? = nil, excludeFromProgression: Bool? = nil,
        plannedSets: [BackupPlannedSet] = []
    ) {
        self.order = order
        self.exerciseSeedID = exerciseSeedID
        self.exerciseName = exerciseName
        self.supersetGroup = supersetGroup
        self.restOverrideSeconds = restOverrideSeconds
        self.note = note
        self.progressionRuleJSON = progressionRuleJSON
        self.stallJSON = stallJSON
        self.trainingMaxKg = trainingMaxKg
        self.excludeFromProgression = excludeFromProgression
        self.plannedSets = plannedSets
    }
}

public struct BackupRoutine: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var progressionRule: String
    public var repRangeLow: Int
    public var repRangeHigh: Int
    /// Opaque JSON for the routine-level `GymCore.ProgressionRule`; nil means the legacy
    /// `progressionRule` name is authoritative.
    public var progressionRuleJSON: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var sortOrder: Int
    public var isArchived: Bool?
    /// Stable identity for starter/shared routines so a re-import merges instead of duplicating.
    public var importedFromID: UUID?
    /// Card glyph: an SF Symbol name and a tint key. Nil in files written before the glyph
    /// existed; the importer falls back to the app's defaults.
    public var symbolName: String?
    public var tint: String?
    public var exercises: [BackupRoutineExercise]

    public init(
        id: UUID, name: String, notes: String = "", progressionRule: String = "doubleProgression",
        repRangeLow: Int = 6, repRangeHigh: Int = 8, progressionRuleJSON: String? = nil,
        createdAt: Date? = nil, updatedAt: Date? = nil, sortOrder: Int = 0, isArchived: Bool? = nil,
        importedFromID: UUID? = nil, symbolName: String? = nil, tint: String? = nil,
        exercises: [BackupRoutineExercise] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.progressionRule = progressionRule
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.progressionRuleJSON = progressionRuleJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.importedFromID = importedFromID
        self.symbolName = symbolName
        self.tint = tint
        self.exercises = exercises
    }
}

public struct BackupSetLog: Codable, Sendable, Identifiable {
    public var id: UUID
    public var order: Int
    public var kind: String
    public var weightKg: Double
    public var reps: Int
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var assistanceKg: Double?
    public var rpe: Double?
    public var isCompleted: Bool
    public var completedAt: Date?
    public var prescriptionReason: String

    public init(
        id: UUID, order: Int, kind: String, weightKg: Double = 0, reps: Int = 0,
        durationSeconds: Int? = nil, distanceMeters: Double? = nil, assistanceKg: Double? = nil,
        rpe: Double? = nil, isCompleted: Bool = false, completedAt: Date? = nil,
        prescriptionReason: String = ""
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.assistanceKg = assistanceKg
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.prescriptionReason = prescriptionReason
    }
}

public struct BackupWorkoutExercise: Codable, Sendable, Identifiable {
    public var id: UUID
    public var order: Int
    public var supersetGroup: Int?
    public var note: String
    public var wasSubstitution: Bool
    /// Whether this exercise was a detector-planned deload rather than a normal session — it must
    /// stay excluded from progression history after a restore. Optional so decoding a backup
    /// exported before this field existed doesn't fail on a missing key; nil means "not a planned
    /// deload", same as `DaGym.WorkoutExerciseModel.wasPlannedDeload`'s `false` default.
    public var wasPlannedDeload: Bool?
    /// Mirrors `DaGym.WorkoutExerciseModel.excludedFromProgression` — a rehab or accessory session
    /// that must stay out of progression history after a restore. Optional: nil (an older export)
    /// means false.
    public var excludedFromProgression: Bool?
    /// Mirrors `DaGym.WorkoutExerciseModel.routineID`, so a session built from more than one
    /// routine still groups by routine in History after a restore. Optional for the same reason.
    public var routineID: UUID?
    public var exerciseSeedID: String?
    public var exerciseName: String
    public var sets: [BackupSetLog]

    public init(
        id: UUID, order: Int, supersetGroup: Int? = nil, note: String = "",
        wasSubstitution: Bool = false, wasPlannedDeload: Bool? = nil,
        excludedFromProgression: Bool? = nil, routineID: UUID? = nil, exerciseSeedID: String? = nil,
        exerciseName: String, sets: [BackupSetLog] = []
    ) {
        self.id = id
        self.order = order
        self.supersetGroup = supersetGroup
        self.note = note
        self.wasSubstitution = wasSubstitution
        self.wasPlannedDeload = wasPlannedDeload
        self.excludedFromProgression = excludedFromProgression
        self.routineID = routineID
        self.exerciseSeedID = exerciseSeedID
        self.exerciseName = exerciseName
        self.sets = sets
    }
}

/// A performed session. Kept as its own id so re-importing the same file
/// can skip workouts already present (`BackupService`).
public struct BackupWorkout: Codable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var notes: String
    public var isBackfilled: Bool
    public var routineID: UUID?
    public var routineName: String
    public var bodyweightKg: Double?
    public var sourceDevice: String
    /// Apple Health workout identifier, so a restore doesn't write the session to Health twice.
    public var healthKitID: String?
    public var exercises: [BackupWorkoutExercise]

    public init(
        id: UUID, title: String, startedAt: Date, endedAt: Date? = nil, notes: String = "",
        isBackfilled: Bool = false, routineID: UUID? = nil, routineName: String = "",
        bodyweightKg: Double? = nil, sourceDevice: String = "iPhone", healthKitID: String? = nil,
        exercises: [BackupWorkoutExercise] = []
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.isBackfilled = isBackfilled
        self.routineID = routineID
        self.routineName = routineName
        self.bodyweightKg = bodyweightKg
        self.sourceDevice = sourceDevice
        self.healthKitID = healthKitID
        self.exercises = exercises
    }
}

public struct BackupBodyMeasurement: Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var bodyweightKg: Double?
    public var source: String

    public init(id: UUID, date: Date, bodyweightKg: Double? = nil, source: String = "manual") {
        self.id = id
        self.date = date
        self.bodyweightKg = bodyweightKg
        self.source = source
    }
}

public struct BackupEquipmentProfile: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isActive: Bool
    public var barKg: Double
    public var availableEquipment: [String]
    public var plateStockKg: [Double]
    public var plateCounts: [Int]
    public var collarsKg: Double
    public var createdAt: Date
    /// `EquipmentProfileModel.seedKey` — "gym"/"home" for a seeded profile, `nil` for one the
    /// user made. Carried through a backup so a restored profile keeps its seed identity
    /// instead of arriving unkeyed and being re-derived by a guess on the restoring device.
    /// Absent from backups written before this field existed, which decode as `nil`.
    public var seedKey: String?

    public init(
        id: UUID, name: String, isActive: Bool = false, barKg: Double = 20,
        availableEquipment: [String] = [], plateStockKg: [Double] = [], plateCounts: [Int] = [],
        collarsKg: Double = 0, createdAt: Date = Date(), seedKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.barKg = barKg
        self.availableEquipment = availableEquipment
        self.plateStockKg = plateStockKg
        self.plateCounts = plateCounts
        self.collarsKg = collarsKg
        self.createdAt = createdAt
        self.seedKey = seedKey
    }
}

public struct BackupProgramWeek: Codable, Sendable, Identifiable {
    public var id: UUID
    public var index: Int
    public var kind: String

    public init(id: UUID, index: Int, kind: String) {
        self.id = id
        self.index = index
        self.kind = kind
    }
}

/// A multi-week program and which routines it cycles through.
public struct BackupProgram: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var weeks: Int
    public var startedAt: Date?
    public var completedAt: Date?
    public var isActive: Bool
    public var routineIDs: [UUID]
    public var createdAt: Date
    public var programWeeks: [BackupProgramWeek]

    public init(
        id: UUID, name: String, weeks: Int, startedAt: Date? = nil, completedAt: Date? = nil,
        isActive: Bool = false, routineIDs: [UUID] = [], createdAt: Date = Date(),
        programWeeks: [BackupProgramWeek] = []
    ) {
        self.id = id
        self.name = name
        self.weeks = weeks
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isActive = isActive
        self.routineIDs = routineIDs
        self.createdAt = createdAt
        self.programWeeks = programWeeks
    }
}

public struct BackupAchievement: Codable, Sendable, Identifiable {
    public var id: UUID
    public var milestoneID: String
    public var tier: String
    public var earnedAt: Date
    public var workoutID: UUID?

    public init(id: UUID, milestoneID: String, tier: String, earnedAt: Date, workoutID: UUID? = nil) {
        self.id = id
        self.milestoneID = milestoneID
        self.tier = tier
        self.earnedAt = earnedAt
        self.workoutID = workoutID
    }
}

/// The weekly schedule as the app stores it (opaque JSON), newest row only.
public struct BackupSchedule: Codable, Sendable {
    public var scheduleJSON: String
    public var updatedAt: Date

    public init(scheduleJSON: String, updatedAt: Date) {
        self.scheduleJSON = scheduleJSON
        self.updatedAt = updatedAt
    }
}
