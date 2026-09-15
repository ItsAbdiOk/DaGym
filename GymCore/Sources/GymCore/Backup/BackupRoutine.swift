import Foundation

public struct BackupPlannedSet: Codable, Sendable {
    public var order: Int
    public var kind: String
    public var targetReps: Int?
    public var targetRepsHigh: Int?
    public var targetWeightKg: Double?
    public var targetRPE: Double?
    public var targetSeconds: Int?
    /// Cardio target, canonical metres. Absent in files written before it existed.
    public var targetDistanceMeters: Double?

    public init(
        order: Int, kind: String, targetReps: Int? = nil, targetRepsHigh: Int? = nil,
        targetWeightKg: Double? = nil, targetRPE: Double? = nil, targetSeconds: Int? = nil,
        targetDistanceMeters: Double? = nil
    ) {
        self.order = order
        self.kind = kind
        self.targetReps = targetReps
        self.targetRepsHigh = targetRepsHigh
        self.targetWeightKg = targetWeightKg
        self.targetRPE = targetRPE
        self.targetSeconds = targetSeconds
        self.targetDistanceMeters = targetDistanceMeters
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
    /// The `ProgressionRule` override on this exercise as a nested value (format 2); nil defers
    /// to the routine's rule. Read through `resolvedRule`, which also understands the format-1
    /// `progressionRuleJSON` string.
    public var rule: ProgressionRule?
    /// The engine's per-exercise memory as a nested value (format 2), so a restore doesn't
    /// reset stall/deload counters; nil (never persisted) means "no memory yet". Read through
    /// `resolvedStall`, which also understands the format-1 `stallJSON` string.
    public var stall: StallState?
    /// Format 1: opaque JSON for the rule override. Still read; no longer written.
    public var progressionRuleJSON: String?
    /// Format 1: opaque JSON for the stall state, `"{}"` for none. Still read; no longer written.
    public var stallJSON: String?
    /// The rolling training max for `.percentOfTrainingMax`, nil until first set. Mirrors
    /// `DaGym.RoutineExerciseModel.trainingMaxKg`.
    public var trainingMaxKg: Double?
    /// Planned-deload flag on the slot; nil (older export) means false.
    public var excludeFromProgression: Bool?
    public var plannedSets: [BackupPlannedSet]

    public init(
        order: Int, exerciseSeedID: String? = nil, exerciseName: String, supersetGroup: Int? = nil,
        restOverrideSeconds: Int? = nil, note: String = "", rule: ProgressionRule? = nil,
        stall: StallState? = nil, progressionRuleJSON: String? = nil, stallJSON: String? = nil,
        trainingMaxKg: Double? = nil, excludeFromProgression: Bool? = nil,
        plannedSets: [BackupPlannedSet] = []
    ) {
        self.order = order
        self.exerciseSeedID = exerciseSeedID
        self.exerciseName = exerciseName
        self.supersetGroup = supersetGroup
        self.restOverrideSeconds = restOverrideSeconds
        self.note = note
        self.rule = rule
        self.stall = stall
        self.progressionRuleJSON = progressionRuleJSON
        self.stallJSON = stallJSON
        self.trainingMaxKg = trainingMaxKg
        self.excludeFromProgression = excludeFromProgression
        self.plannedSets = plannedSets
    }

    /// The rule override, from the nested value or — for a format-1 file — the JSON string.
    public var resolvedRule: ProgressionRule? {
        rule ?? BackupLegacyJSON.decode(ProgressionRule.self, from: progressionRuleJSON)
    }

    /// The stall memory, from the nested value or the format-1 string; a blank string or `"{}"`
    /// is the engine's "no memory yet".
    public var resolvedStall: StallState {
        stall ?? BackupLegacyJSON.decode(StallState.self, from: stallJSON) ?? StallState()
    }
}

public struct BackupRoutine: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var progressionRule: String
    public var repRangeLow: Int
    public var repRangeHigh: Int
    /// The routine-level `ProgressionRule` as a nested value (format 2). Read through
    /// `resolvedRule`; nil there means the legacy `progressionRule` name is authoritative.
    public var rule: ProgressionRule?
    /// Format 1: opaque JSON for the routine-level rule. Still read; no longer written.
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
        repRangeLow: Int = 6, repRangeHigh: Int = 8, rule: ProgressionRule? = nil,
        progressionRuleJSON: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil,
        sortOrder: Int = 0, isArchived: Bool? = nil, importedFromID: UUID? = nil, symbolName: String? = nil,
        tint: String? = nil, exercises: [BackupRoutineExercise] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.progressionRule = progressionRule
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.rule = rule
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

    /// The routine's rule, from the nested value or — for a format-1 file — the JSON string.
    public var resolvedRule: ProgressionRule? {
        rule ?? BackupLegacyJSON.decode(ProgressionRule.self, from: progressionRuleJSON)
    }
}

/// Decodes the JSON-in-JSON strings format 1 used for rules, stall state and the schedule. A
/// value that doesn't decode reads as absent, never as a failed restore: the string was written
/// by an app that may have since renamed a case, and a routine is worth more than its rule.
enum BackupLegacyJSON {
    static func decode<Value: Decodable>(_ type: Value.Type, from json: String?) -> Value? {
        guard let json, !json.isEmpty, json != "{}", let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
