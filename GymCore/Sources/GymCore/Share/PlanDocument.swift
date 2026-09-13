import Foundation

/// A shareable training plan (plan.md §6.8) — one routine, or a whole multi-week program, sent
/// via Messages/AirDrop/the share sheet as a `.gymplan` file. Pure value types only, same shape
/// as `BackupDocument` but scoped to *plans*: never workouts, weigh-ins or photos.
///
/// Exercises travel two ways: a seeded exercise is referenced by `seedID` (the recipient already
/// has it); a custom exercise travels as a full `PlanExercise` row, including its instructions,
/// so the recipient gets a usable exercise even with no shared library entry to match against.
public struct PlanDocument: Codable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var appVersion: String

    /// Custom exercises referenced by `routines`, full definitions. Seeded exercises are not
    /// listed here — they travel as a `seedID` on the routine-exercise slot instead.
    public var exercises: [PlanExercise]
    public var routines: [PlanRoutine]
    /// Set when this document is a program export; its `routineIDs` reference `routines` above.
    public var program: PlanProgram?

    public init(
        formatVersion: Int = PlanDocument.currentFormatVersion, exportedAt: Date, appVersion: String,
        exercises: [PlanExercise] = [], routines: [PlanRoutine] = [], program: PlanProgram? = nil
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.exercises = exercises
        self.routines = routines
        self.program = program
    }
}

/// A custom exercise carried along with a shared routine — nil `seedID` always, since seeded
/// exercises are referenced by id instead of duplicated into the file.
public struct PlanExercise: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var equipment: String
    public var mechanic: String?
    public var loggingStyle: String
    public var isPerSide: Bool
    public var barType: String?
    public var incrementKg: Double
    public var restSeconds: Int
    public var instructions: String
    public var notes: String

    public init(
        id: UUID, name: String, primaryMuscles: [String] = [], secondaryMuscles: [String] = [],
        equipment: String = "other", mechanic: String? = nil, loggingStyle: String = "weightReps",
        isPerSide: Bool = false, barType: String? = nil, incrementKg: Double = 2.5,
        restSeconds: Int = 150, instructions: String = "", notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.mechanic = mechanic
        self.loggingStyle = loggingStyle
        self.isPerSide = isPerSide
        self.barType = barType
        self.incrementKg = incrementKg
        self.restSeconds = restSeconds
        self.instructions = instructions
        self.notes = notes
    }
}

public struct PlanSet: Codable, Sendable {
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

/// One exercise slot inside a `PlanRoutine`. Resolved on import by `exerciseSeedID` first, then
/// by `exerciseName` — an unknown seed falls back to creating a custom exercise from the name.
public struct PlanRoutineExercise: Codable, Sendable {
    public var order: Int
    public var exerciseSeedID: String?
    public var exerciseName: String
    public var supersetGroup: Int?
    public var restOverrideSeconds: Int?
    public var note: String
    /// Opaque JSON for a `GymCore.ProgressionRule` override on this exercise; nil defers to the
    /// routine's rule. Encoded/decoded by the app layer (`ProgressionRuleCoding`), not here —
    /// this type has no dependency on that rule's own definition.
    public var ruleJSON: String?
    public var sets: [PlanSet]

    public init(
        order: Int, exerciseSeedID: String? = nil, exerciseName: String, supersetGroup: Int? = nil,
        restOverrideSeconds: Int? = nil, note: String = "", ruleJSON: String? = nil,
        sets: [PlanSet] = []
    ) {
        self.order = order
        self.exerciseSeedID = exerciseSeedID
        self.exerciseName = exerciseName
        self.supersetGroup = supersetGroup
        self.restOverrideSeconds = restOverrideSeconds
        self.note = note
        self.ruleJSON = ruleJSON
        self.sets = sets
    }
}

/// A shared routine. `id` is stable across re-exports of the same routine — the app layer uses
/// it (via `RoutineModel.importedFromID`) to recognise "I already imported this" and skip
/// creating a duplicate on a second import of the same file.
public struct PlanRoutine: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var progressionRule: String
    public var repRangeLow: Int
    public var repRangeHigh: Int
    /// Opaque JSON for the routine's `GymCore.ProgressionRule`; nil falls back to
    /// `progressionRule`/`repRangeLow`/`repRangeHigh`, mirroring `RoutineModel`.
    public var ruleJSON: String?
    public var sortOrder: Int
    public var exercises: [PlanRoutineExercise]

    public init(
        id: UUID, name: String, notes: String = "", progressionRule: String = "doubleProgression",
        repRangeLow: Int = 6, repRangeHigh: Int = 8, ruleJSON: String? = nil, sortOrder: Int = 0,
        exercises: [PlanRoutineExercise] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.progressionRule = progressionRule
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.ruleJSON = ruleJSON
        self.sortOrder = sortOrder
        self.exercises = exercises
    }
}

public struct PlanProgramWeek: Codable, Sendable {
    public var index: Int
    /// "normal" / "deload" / "rest" — `ProgramWeekKind.rawValue`.
    public var kind: String

    public init(index: Int, kind: String) {
        self.index = index
        self.kind = kind
    }
}

/// A shared multi-week program. `routineIDs` is the day-cycle mapping, referencing `PlanRoutine`
/// ids in the same document's `routines` array (in day order, duplicates allowed).
public struct PlanProgram: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var weeks: Int
    public var routineIDs: [UUID]
    public var programWeeks: [PlanProgramWeek]

    public init(
        id: UUID, name: String, weeks: Int, routineIDs: [UUID] = [],
        programWeeks: [PlanProgramWeek] = []
    ) {
        self.id = id
        self.name = name
        self.weeks = weeks
        self.routineIDs = routineIDs
        self.programWeeks = programWeeks
    }
}
