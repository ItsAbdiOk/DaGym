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
        licence: String = "", authors: [String] = []
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
    }

    /// "Chest · front delts · triceps"
    var muscleLine: String {
        (primary + secondary).map { $0 == primary.first ? $0.displayName : $0.displayName.lowercased() }
            .joined(separator: " · ")
    }

    /// Intensity map for the body map thumbnail.
    var hitMap: [Muscle: Double] {
        var map: [Muscle: Double] = [:]
        primary.forEach { map[$0] = 1 }
        secondary.forEach { map[$0] = 0.45 }
        return map
    }
}

struct SetEntry: Identifiable, Hashable {
    let id: UUID
    var kind: SetKind
    var weightKg: Double
    var reps: Int
    var effort: Effort?
    var isDone = false
    /// Ghost of the previous session's same set, e.g. "80 × 8".
    var previous: String?
    /// Timed holds.
    var durationSeconds: Int?
    var targetSeconds: Int?

    init(
        id: UUID = UUID(), kind: SetKind = .working, weightKg: Double, reps: Int,
        effort: Effort? = nil, isDone: Bool = false, previous: String? = nil,
        durationSeconds: Int? = nil, targetSeconds: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.effort = effort
        self.isDone = isDone
        self.previous = previous
        self.durationSeconds = durationSeconds
        self.targetSeconds = targetSeconds
    }

    /// Converted for the shared `GymCore` stats helpers. `date` isn't tracked
    /// per set here, so a placeholder is used — callers that need it (PR
    /// evaluation) build `PerformedSet` directly with the workout's date.
    var performed: GymCore.PerformedSet {
        GymCore.PerformedSet(
            kind: kind, weightKg: weightKg, reps: reps, durationSeconds: durationSeconds, date: Date()
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
    /// "80 × 8,8,7 · 77.5 × 8,8,8 · 77.5 × 8,7,7"
    var lastSessions: [String] = []
    var sparkline: [Double] = []
    /// True once this exercise has been swapped mid-workout.
    var wasSubstitution = false

    init(
        id: UUID = UUID(), exercise: ExerciseInfo, sets: [SetEntry], supersetGroup: Int? = nil,
        note: String? = nil, whyTitle: String? = nil, whyBody: String? = nil,
        lastSessions: [String] = [], sparkline: [Double] = [], wasSubstitution: Bool = false
    ) {
        self.id = id
        self.exercise = exercise
        self.sets = sets
        self.supersetGroup = supersetGroup
        self.note = note
        self.whyTitle = whyTitle
        self.whyBody = whyBody
        self.lastSessions = lastSessions
        self.sparkline = sparkline
        self.wasSubstitution = wasSubstitution
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

    init(
        id: UUID = UUID(), name: String, exercises: [ExerciseInfo], setCount: Int,
        estimatedMinutes: Int, progressionRule: String, progressionDetail: String, weekLabel: String? = nil,
        exerciseSetCounts: [Int] = []
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

    init(
        id: UUID = UUID(), title: String, startedAt: Date, endedAt: Date? = nil,
        exercises: [WorkoutExerciseEntry] = [], notes: String = "", isBackfilled: Bool = false,
        prCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
        self.notes = notes
        self.isBackfilled = isBackfilled
        self.prCount = prCount
    }

    var durationMinutes: Int {
        guard let endedAt else { return 0 }
        return max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))
    }

    var volumeKg: Double {
        exercises.flatMap(\.sets).filter { $0.isDone && $0.kind.countsTowardStats }
            .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    var setsDone: Int { exercises.reduce(0) { $0 + $1.doneCount } }
}

struct PersonalRecordInfo: Identifiable, Hashable {
    let id = UUID()
    var exerciseName: String
    var line: String
}

/// State of one in-progress session. Drives the Active Workout screen.
@Observable
@MainActor
final class WorkoutSession {
    var title: String
    var subtitle: String
    var startedAt: Date
    var exercises: [WorkoutExerciseEntry]
    var effortScale: Effort.Scale = .rpe
    /// True for a session logged after the fact via "Log a Past Workout".
    var isBackfilled: Bool
    /// The `WorkoutModel` this session is backed by, once persisted.
    var workoutID: UUID?

    // Rest timer
    var restRemaining: Int = 0
    var restTotal: Int = 0
    var restNextLabel: String = ""
    var isResting: Bool { restRemaining > 0 }

    // PR banner
    var prBanner: PersonalRecordInfo?

    init(
        title: String, subtitle: String, startedAt: Date, exercises: [WorkoutExerciseEntry],
        isBackfilled: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.startedAt = startedAt
        self.exercises = exercises
        self.isBackfilled = isBackfilled
    }

    /// Timed-hold live timer, or nil when no hold is in progress.
    var timedHold: TimedHoldState?

    struct TimedHoldState {
        var exerciseID: UUID
        var setID: UUID
        var targetSeconds: Int?
        var leadIn: Int
        var elapsed: Int
        var isPaused: Bool
    }

    var volumeKg: Double {
        GymCore.SessionStats.volumeKg(exercises.flatMap(\.sets).filter(\.isDone).map(\.performed))
    }

    var setsDone: Int { exercises.reduce(0) { $0 + $1.doneCount } }
    var setsTotal: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var prCount: Int { prBanner == nil ? 0 : 1 }

    /// Elapsed seconds since the session started, as of `date`.
    func elapsedSeconds(at date: Date = Date()) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt)))
    }

    /// Index of the first exercise with an incomplete set.
    var onDeckIndex: Int? { exercises.firstIndex { !$0.isComplete } }

    /// Muscles hit so far, weighted by completed sets.
    var musclesHit: [Muscle: Double] {
        let entries = exercises.map {
            (primary: $0.exercise.primary, secondary: $0.exercise.secondary, completedCount: $0.doneCount)
        }
        return GymCore.SessionStats.musclesHit(sets: entries)
    }

    func completeSet(exerciseID: UUID, setID: UUID, effort: Effort? = nil) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].isDone = true
        if let effort { exercises[ei].sets[si].effort = effort }
        Haptics.setDone()
        startRest(seconds: exercises[ei].exercise.restSeconds, after: ei, set: si)
    }

    func uncompleteSet(exerciseID: UUID, setID: UUID) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].isDone = false
    }

    func startRest(seconds: Int, after exerciseIndex: Int, set setIndex: Int) {
        restTotal = seconds
        restRemaining = seconds
        let ex = exercises[exerciseIndex]
        if setIndex + 1 < ex.sets.count {
            let next = ex.sets[setIndex + 1]
            restNextLabel = "Next \(Self.format(next.weightKg)) × \(next.reps)"
        } else if exerciseIndex + 1 < exercises.count {
            restNextLabel = "Next \(exercises[exerciseIndex + 1].exercise.name)"
        } else {
            restNextLabel = "Last set done"
        }
    }

    func tickRest() {
        guard restRemaining > 0 else { return }
        restRemaining -= 1
        if restRemaining <= 3, restRemaining > 0 { Haptics.restTick() }
        if restRemaining == 0 { Haptics.restEnd() }
    }

    func adjustRest(by delta: Int) {
        restRemaining = max(0, restRemaining + delta)
        restTotal = max(restTotal, restRemaining)
        Haptics.step()
    }

    func skipRest() {
        restRemaining = 0
        Haptics.confirm()
    }

    static func format(_ kg: Double) -> String {
        kg == kg.rounded() ? String(Int(kg)) : String(format: "%.1f", kg)
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
