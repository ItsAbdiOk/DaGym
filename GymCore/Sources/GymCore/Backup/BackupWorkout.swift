import Foundation

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
    /// Treadmill/stair incline for a cardio set. Absent in files written before it existed.
    public var inclinePercent: Double?

    public init(
        id: UUID, order: Int, kind: String, weightKg: Double = 0, reps: Int = 0,
        durationSeconds: Int? = nil, distanceMeters: Double? = nil, assistanceKg: Double? = nil,
        rpe: Double? = nil, isCompleted: Bool = false, completedAt: Date? = nil,
        prescriptionReason: String = "", inclinePercent: Double? = nil
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
        self.inclinePercent = inclinePercent
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
