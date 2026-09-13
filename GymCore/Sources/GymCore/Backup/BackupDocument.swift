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

    public init(
        formatVersion: Int = BackupDocument.currentFormatVersion,
        exportedAt: Date,
        appVersion: String,
        exercises: [BackupExercise] = [],
        routines: [BackupRoutine] = [],
        workouts: [BackupWorkout] = [],
        bodyMeasurements: [BackupBodyMeasurement] = [],
        equipmentProfiles: [BackupEquipmentProfile] = [],
        preferences: BackupPreferences
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
    public var plannedSets: [BackupPlannedSet]

    public init(
        order: Int, exerciseSeedID: String? = nil, exerciseName: String, supersetGroup: Int? = nil,
        restOverrideSeconds: Int? = nil, note: String = "", plannedSets: [BackupPlannedSet] = []
    ) {
        self.order = order
        self.exerciseSeedID = exerciseSeedID
        self.exerciseName = exerciseName
        self.supersetGroup = supersetGroup
        self.restOverrideSeconds = restOverrideSeconds
        self.note = note
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
    public var sortOrder: Int
    public var exercises: [BackupRoutineExercise]

    public init(
        id: UUID, name: String, notes: String = "", progressionRule: String = "doubleProgression",
        repRangeLow: Int = 6, repRangeHigh: Int = 8, sortOrder: Int = 0,
        exercises: [BackupRoutineExercise] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.progressionRule = progressionRule
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.sortOrder = sortOrder
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
    public var exerciseSeedID: String?
    public var exerciseName: String
    public var sets: [BackupSetLog]

    public init(
        id: UUID, order: Int, supersetGroup: Int? = nil, note: String = "",
        wasSubstitution: Bool = false, exerciseSeedID: String? = nil, exerciseName: String,
        sets: [BackupSetLog] = []
    ) {
        self.id = id
        self.order = order
        self.supersetGroup = supersetGroup
        self.note = note
        self.wasSubstitution = wasSubstitution
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
    public var routineName: String
    public var bodyweightKg: Double?
    public var sourceDevice: String
    public var exercises: [BackupWorkoutExercise]

    public init(
        id: UUID, title: String, startedAt: Date, endedAt: Date? = nil, notes: String = "",
        isBackfilled: Bool = false, routineName: String = "", bodyweightKg: Double? = nil,
        sourceDevice: String = "iPhone", exercises: [BackupWorkoutExercise] = []
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.isBackfilled = isBackfilled
        self.routineName = routineName
        self.bodyweightKg = bodyweightKg
        self.sourceDevice = sourceDevice
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

    public init(
        id: UUID, name: String, isActive: Bool = false, barKg: Double = 20,
        availableEquipment: [String] = [], plateStockKg: [Double] = [], plateCounts: [Int] = [],
        collarsKg: Double = 0, createdAt: Date = Date()
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
    }
}

/// Snapshot of `DaGym.Preferences`, duplicated here (rather than depending
/// on the app target) so `GymCore` stays UI/app-free.
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
