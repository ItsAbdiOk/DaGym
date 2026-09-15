import Foundation

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
    /// `ExerciseModel.machine` — the `Machine` raw value a custom exercise (or a seeded row the
    /// lifter re-tagged) needs. Absent from backups written before stations existed.
    public var machine: String?

    public init(
        id: UUID, seedID: String? = nil, name: String, primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [], equipment: String = "other", mechanic: String? = nil,
        loggingStyle: String = "weightReps", isPerSide: Bool = false, isCustom: Bool = false,
        isFavorite: Bool = false, barType: String? = nil, incrementKg: Double = 2.5,
        restSeconds: Int = 150, instructions: String = "", notes: String = "",
        createdAt: Date = Date(), machine: String? = nil
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
        self.machine = machine
    }
}
