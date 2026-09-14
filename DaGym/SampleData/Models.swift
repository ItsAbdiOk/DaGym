import Foundation
import GymCore

// Lightweight view models used to drive the screens until the SwiftData
// model lands. Everything here is plain value types plus one observable
// session so the UI can be reviewed with realistic data.

struct ExerciseInfo: Identifiable, Hashable {
    let id: UUID
    var name: String
    var primary: [Muscle]
    var secondary: [Muscle]
    var equipment: String
    var incrementKg: Double = 2.5
    var restSeconds: Int = 150
    var bar: Bar? = .olympic
    var isFavorite = false
    var isCustom = false
    var isPerSide = false
    var bestE1RM: Double?
    var bestSet: String?
    var sessions = 0
    var instructions = ""
    var loggingStyle: LoggingStyle = .weightReps
    /// Provenance of `instructions`, e.g. "wger".
    var dataSource = ""
    var sourceURL = ""
    /// Licence covering `instructions` when sourced externally, e.g. "CC-BY-SA 4.0".
    var licence = ""
    var authors: [String] = []
    /// The seeded JSON id (`ExerciseModel.seedID`), used to look up illustrated art in
    /// `ExerciseArtCatalog`. Nil for custom exercises and any fixture built without one.
    var seedID: String?

    enum LoggingStyle: String, CaseIterable {
        case weightReps = "Weight × reps"
        case bodyweightReps = "Bodyweight reps"
        case assisted = "Assisted"
        case weightedBodyweight = "Weighted bodyweight"
        case timedHold = "Timed hold"
        case cardio = "Cardio"
    }

    init(
        id: UUID = UUID(), name: String, primary: [Muscle], secondary: [Muscle] = [],
        equipment: String, incrementKg: Double = 2.5, restSeconds: Int = 150, bar: Bar? = .olympic,
        isFavorite: Bool = false, isCustom: Bool = false, isPerSide: Bool = false, bestE1RM: Double? = nil,
        bestSet: String? = nil, sessions: Int = 0, instructions: String = "",
        loggingStyle: LoggingStyle = .weightReps, dataSource: String = "", sourceURL: String = "",
        licence: String = "", authors: [String] = [], seedID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
        self.equipment = equipment
        self.incrementKg = incrementKg
        self.restSeconds = restSeconds
        self.bar = bar
        self.isFavorite = isFavorite
        self.isCustom = isCustom
        self.isPerSide = isPerSide
        self.bestE1RM = bestE1RM
        self.bestSet = bestSet
        self.sessions = sessions
        self.instructions = instructions
        self.loggingStyle = loggingStyle
        self.dataSource = dataSource
        self.sourceURL = sourceURL
        self.licence = licence
        self.authors = authors
        self.seedID = seedID
    }

    /// "Chest · front delts · triceps"
    var muscleLine: String {
        (primary + secondary).map { $0 == primary.first ? $0.displayName : $0.displayName.lowercased() }
            .joined(separator: " · ")
    }

    /// Intensity map for the body map thumbnail. A primary mover always reads 1; a secondary
    /// one reads `SessionStats.secondaryMuscleShare`.
    ///
    /// Primary wins unconditionally. Writing primary first and secondary second let a muscle
    /// listed in both lists be overwritten by the lower value — a barbell curl tagged
    /// `biceps`/`biceps` drew its biceps at the secondary step instead of full.
    var hitMap: [Muscle: Double] {
        var map: [Muscle: Double] = [:]
        secondary.forEach { map[$0] = SessionStats.secondaryMuscleShare }
        primary.forEach { map[$0] = 1 }
        return map
    }

    /// `GymCore.LoadingStyle` for `WarmupGenerator`.
    ///
    /// `loggingStyle` decides first, because it says what the logged number *means*: an
    /// assisted pull-up is usually filed under "machine", and ramping its assistance up makes
    /// every warm-up harder than the working set; a timed hold filed under "barbell" would get
    /// rep-based warm-ups with no duration. Only once the number is known to be a load does the
    /// kit decide the ramp — and then every kind is mapped, so a kettlebell or an EZ-bar lift
    /// gets a ramp instead of silently getting none.
    var warmupLoadingStyle: LoadingStyle {
        switch loggingStyle {
        case .assisted: return .assisted
        case .timedHold, .cardio: return .timed
        case .bodyweightReps, .weightedBodyweight: return .bodyweight
        case .weightReps: break
        }
        switch equipment.lowercased() {
        case "barbell", "ezbar", "ez bar", "smith machine", "trap bar":
            return .barbell(bar: bar ?? .olympic)
        case "dumbbell", "kettlebell":
            return .dumbbell
        case "bodyweight", "bands":
            return .bodyweight
        default:
            // Machine, cable, "other": a fixed-step ramp with no empty-bar set.
            return .machine
        }
    }
}

struct SetEntry: Identifiable, Hashable {
    let id: UUID
    var kind: SetKind
    var weightKg: Double
    var reps: Int
    var effort: Effort?
    var isDone = false
    /// Ghost of the previous session's same set: raw data, formatted at
    /// display time in the user's unit (see `SetRow`).
    var previousWeightKg: Double?
    var previousReps: Int?
    /// Timed holds.
    var durationSeconds: Int?
    var targetSeconds: Int?
    /// Short "why" headline for this set's prescribed numbers (e.g. "+2.5 kg"), synced onto
    /// `SetLogModel.prescriptionReason` (plan.md §6.5).
    var prescriptionReason: String = ""
    /// `.assisted` exercises: assistance dialed in on the machine/band, in kg (synced onto
    /// `SetLogModel.assistanceKg`).
    var assistanceKg: Double?

    init(
        id: UUID = UUID(), kind: SetKind = .working, weightKg: Double, reps: Int,
        effort: Effort? = nil, isDone: Bool = false, previousWeightKg: Double? = nil,
        previousReps: Int? = nil, durationSeconds: Int? = nil, targetSeconds: Int? = nil,
        prescriptionReason: String = "", assistanceKg: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.effort = effort
        self.isDone = isDone
        self.previousWeightKg = previousWeightKg
        self.previousReps = previousReps
        self.durationSeconds = durationSeconds
        self.targetSeconds = targetSeconds
        self.prescriptionReason = prescriptionReason
        self.assistanceKg = assistanceKg
    }

    /// Converted for the shared `GymCore` stats helpers. `date` isn't tracked
    /// per set here, so a placeholder is used — callers that need it (PR
    /// evaluation) build `PerformedSet` directly with the workout's date.
    var performed: GymCore.PerformedSet {
        GymCore.PerformedSet(
            kind: kind, weightKg: weightKg, reps: reps, durationSeconds: durationSeconds,
            assistanceKg: assistanceKg, date: Date()
        )
    }
}

struct WorkoutExerciseEntry: Identifiable, Hashable {
    let id: UUID
    var exercise: ExerciseInfo
    var sets: [SetEntry]
    /// Exercises sharing a group id are a superset.
    var supersetGroup: Int?
    var note: String?
    var whyTitle: String?
    var whyBody: String?
    /// `PrescriptionReason.Kind` behind `whyTitle`/`whyBody`, so a deload back-off styles
    /// differently from a plain increase/repeat (A8).
    var whyKind: PrescriptionReason.Kind?
    /// "80 × 8,8,7 · 77.5 × 8,8,8 · 77.5 × 8,7,7"
    var lastSessions: [String] = []
    var sparkline: [Double] = []
    /// True once this exercise has been swapped mid-workout.
    var wasSubstitution = false
    /// True when this exercise was prescribed as part of a program's planned deload week
    /// (plan.md §6.5) — excluded as the baseline future progression builds from.
    var wasPlannedDeload = false
    /// The routine this exercise was built from, stamped once when the entry is created
    /// (`WorkoutStore.buildEntries(from:)`) and persisted on `WorkoutExerciseModel.routineID`.
    /// Nil for a freestyle exercise or one added mid-workout with no routine slot. Multiple
    /// routines can feed one session (`WorkoutStore.appendRoutine`); this is what lets
    /// `WorkoutDetailView` group a "Push A + Arms" workout by the routine each exercise came
    /// from, and the Live Activity show the on-deck exercise's own routine glyph.
    var routineID: UUID?

    init(
        id: UUID = UUID(), exercise: ExerciseInfo, sets: [SetEntry], supersetGroup: Int? = nil,
        note: String? = nil, whyTitle: String? = nil, whyBody: String? = nil,
        whyKind: PrescriptionReason.Kind? = nil, lastSessions: [String] = [], sparkline: [Double] = [],
        wasSubstitution: Bool = false, wasPlannedDeload: Bool = false, routineID: UUID? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.sets = sets
        self.supersetGroup = supersetGroup
        self.note = note
        self.whyTitle = whyTitle
        self.whyBody = whyBody
        self.whyKind = whyKind
        self.lastSessions = lastSessions
        self.sparkline = sparkline
        self.wasSubstitution = wasSubstitution
        self.wasPlannedDeload = wasPlannedDeload
        self.routineID = routineID
    }

    var doneCount: Int { sets.filter(\.isDone).count }
    var isComplete: Bool { !sets.isEmpty && doneCount == sets.count }
    var isTimed: Bool { exercise.loggingStyle == .timedHold }
}

struct RoutineInfo: Identifiable, Hashable {
    let id: UUID
    var name: String
    var exercises: [ExerciseInfo]
    var setCount: Int
    var estimatedMinutes: Int
    var progressionRule: String
    var progressionDetail: String
    var weekLabel: String?
    /// Planned set count per exercise, index-paired with `exercises`. When
    /// shorter than `exercises` (e.g. sample data), each missing exercise
    /// falls back to a weight of 1 set in `hitMap`.
    var exerciseSetCounts: [Int] = []
    /// Glyph shown on the routine's card and Home's scheduled card: an SF Symbol name and a
    /// `RoutineTint` raw value (see `RoutineGlyph`).
    var symbolName: String = "dumbbell"
    var tint: String = "coral"

    init(
        id: UUID = UUID(), name: String, exercises: [ExerciseInfo], setCount: Int,
        estimatedMinutes: Int, progressionRule: String, progressionDetail: String, weekLabel: String? = nil,
        exerciseSetCounts: [Int] = [], symbolName: String = "dumbbell", tint: String = "coral"
    ) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.setCount = setCount
        self.estimatedMinutes = estimatedMinutes
        self.progressionRule = progressionRule
        self.progressionDetail = progressionDetail
        self.weekLabel = weekLabel
        self.exerciseSetCounts = exerciseSetCounts
        self.symbolName = symbolName
        self.tint = tint
    }

    /// Weighted, normalised "muscles hit" map — see `GymCore.RoutineMuscles.hitMap`.
    var hitMap: [Muscle: Double] {
        let entries = exercises.enumerated().map { index, exercise in
            (
                primary: exercise.primary, secondary: exercise.secondary,
                setCount: exerciseSetCounts.indices.contains(index) ? exerciseSetCounts[index] : 1
            )
        }
        return GymCore.RoutineMuscles.hitMap(exercises: entries)
    }

    /// The "HITS" line, e.g. "Chest, front delts, triceps · light on back".
    var hitSummary: String { GymCore.RoutineMuscles.summary(hitMap: hitMap) }
}

struct WorkoutRecord: Identifiable, Hashable {
    let id: UUID
    var title: String
    var date: Date
    var durationMinutes: Int
    var volumeKg: Double
    var sets: Int
    var prCount: Int

    init(
        id: UUID = UUID(), title: String, date: Date, durationMinutes: Int,
        volumeKg: Double, sets: Int, prCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.durationMinutes = durationMinutes
        self.volumeKg = volumeKg
        self.sets = sets
        self.prCount = prCount
    }
}

/// Full read-only detail for one finished workout, built by
/// `WorkoutStore.workoutDetail(id:)` for `WorkoutDetailView`.
struct WorkoutDetail: Identifiable {
    var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var exercises: [WorkoutExerciseEntry]
    var notes: String
    var isBackfilled: Bool
    var prCount: Int
    /// Glyph + name for every distinct `WorkoutExerciseEntry.routineID` this workout's exercises
    /// carry, for `WorkoutDetailView`'s group headers. Empty for a single-routine or freestyle
    /// workout — see `WorkoutDetail.exerciseGroups`.
    var routineGlyphs: [UUID: RoutineGlyphInfo]

    init(
        id: UUID = UUID(), title: String, startedAt: Date, endedAt: Date? = nil,
        exercises: [WorkoutExerciseEntry] = [], notes: String = "", isBackfilled: Bool = false,
        prCount: Int = 0, routineGlyphs: [UUID: RoutineGlyphInfo] = [:]
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
        self.notes = notes
        self.isBackfilled = isBackfilled
        self.prCount = prCount
        self.routineGlyphs = routineGlyphs
    }

    var durationMinutes: Int {
        guard let endedAt else { return 0 }
        return max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))
    }

    var volumeKg: Double {
        exercises.flatMap(\.sets).filter { $0.isDone && $0.kind.countsTowardStats }
            .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    /// Completed working sets — warm-ups excluded, matching the History row and weekly recap.
    var setsDone: Int {
        exercises.flatMap(\.sets).filter { $0.isDone && $0.kind.countsTowardStats }.count
    }
}

struct PersonalRecordInfo: Identifiable, Hashable {
    let id = UUID()
    var exerciseName: String
    var line: String
}

// `WorkoutSession` (the in-progress session state driving Active Workout) lives in
// `WorkoutSession.swift`, split out to keep this file under the line-count cap.
