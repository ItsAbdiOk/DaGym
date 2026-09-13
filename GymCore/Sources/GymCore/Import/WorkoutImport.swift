import Foundation

/// A third-party app whose CSV export `WorkoutImport` can parse (plan.md §6.8: "Import history
/// from other apps").
public enum ImportSource: String, Sendable, CaseIterable {
    case strong
    case hevy
    case fitNotes

    /// `WorkoutModel.sourceDevice` tag written for workouts created from this source.
    public var sourceDeviceTag: String { "import:\(rawValue)" }

    public var displayName: String {
        switch self {
        case .strong: "Strong"
        case .hevy: "Hevy"
        case .fitNotes: "FitNotes"
        }
    }
}

/// One row that couldn't be turned into a set/workout, kept instead of silently dropped
/// (plan.md §6.8: "nothing is dropped; show a preview + problems before confirming").
public struct ImportProblem: Hashable, Sendable {
    /// 1-based line number in the original file, header included.
    public var line: Int
    public var message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

/// One completed set, already converted to canonical units (kg, seconds, meters).
public struct ImportedSet: Hashable, Sendable {
    public var kind: SetKind
    public var weightKg: Double
    public var reps: Int
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?

    public init(
        kind: SetKind, weightKg: Double, reps: Int, durationSeconds: Int? = nil,
        distanceMeters: Double? = nil, rpe: Double? = nil
    ) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rpe = rpe
    }
}

/// One exercise performed within an imported workout, sets in file order.
public struct ImportedExercise: Hashable, Sendable {
    public var name: String
    public var note: String
    /// The source app's own category/muscle-group label for this exercise, when the format has
    /// one (FitNotes' `Category` column). `nil` for sources that don't carry one (Strong, Hevy);
    /// used as a hint for `ExerciseHints.primaryMuscles` when the name doesn't match anything in
    /// the library.
    public var category: String?
    public var sets: [ImportedSet]

    public init(name: String, note: String = "", category: String? = nil, sets: [ImportedSet]) {
        self.name = name
        self.note = note
        self.category = category
        self.sets = sets
    }
}

/// One workout session decoded from a third-party export, in the app's neutral shape —
/// unmatched to any `ExerciseModel` yet (that happens in `WorkoutImportService`).
public struct ImportedWorkout: Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    public var title: String
    public var notes: String
    public var exercises: [ImportedExercise]

    public init(
        startedAt: Date, endedAt: Date? = nil, title: String, notes: String = "",
        exercises: [ImportedExercise]
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.notes = notes
        self.exercises = exercises
    }
}

/// The result of parsing one CSV file: every workout it produced, plus every row that could not
/// be understood.
public struct ImportResult: Sendable {
    public var source: ImportSource
    public var workouts: [ImportedWorkout]
    public var problems: [ImportProblem]
    /// Rows with nothing measured at all (no weight, reps, time or distance) — skipped rather
    /// than imported as a 0×0 set, and counted here instead of being silently dropped.
    public var emptyRows: Int

    public init(
        source: ImportSource, workouts: [ImportedWorkout], problems: [ImportProblem], emptyRows: Int = 0
    ) {
        self.source = source
        self.workouts = workouts
        self.problems = problems
        self.emptyRows = emptyRows
    }
}

/// Sniffs a CSV export's format from its header line.
public enum ImportDetector {
    /// `nil` when the header matches none of the three supported formats.
    public static func detect(headerLine: String) -> ImportSource? {
        let header = headerLine.lowercased()
        if header.contains("workout name"), header.contains("set order") {
            return .strong
        }
        if header.contains("exercise_title"), header.contains("start_time") {
            return .hevy
        }
        if header.contains("exercise"), header.contains("category"), header.contains("distance unit") {
            return .fitNotes
        }
        return nil
    }
}

/// Entry point: detects the format from the file's header row and dispatches to the matching
/// per-source importer. Returns `nil` only when the header matches no known format at all —
/// individual bad rows within a recognized file become `ImportProblem`s instead.
public enum WorkoutImport {
    public static func parse(csv: String) -> ImportResult? {
        let rows = CSVParser.parse(csv)
        guard let header = rows.first, !header.isEmpty else { return nil }
        guard let source = ImportDetector.detect(headerLine: header.joined(separator: ",")) else {
            return nil
        }
        switch source {
        case .strong: return StrongCSVImporter.parse(rows: rows)
        case .hevy: return HevyCSVImporter.parse(rows: rows)
        case .fitNotes: return FitNotesCSVImporter.parse(rows: rows)
        }
    }
}
