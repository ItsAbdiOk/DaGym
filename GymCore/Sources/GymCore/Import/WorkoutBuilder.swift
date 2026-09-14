import Foundation

/// Accumulates rows into `ImportedWorkout`s, grouping by a caller-supplied key (e.g.
/// "date|workout name") and preserving first-seen order for both workouts and the exercises
/// within each — shared by the three per-source importers so none of them re-implement the
/// grouping logic.
struct WorkoutBuilder {
    private var order: [String] = []
    private var workouts: [String: WorkoutInProgress] = [:]

    /// Groups this row's set into the right workout/exercise by `workoutKey` (unique per
    /// workout, e.g. "date|workout name") and `entry.exerciseName`, creating either as needed.
    mutating func addSet(_ set: ImportedSet, workoutKey: String, entry: WorkoutRowInfo) {
        if workouts[workoutKey] == nil {
            order.append(workoutKey)
            workouts[workoutKey] = WorkoutInProgress(
                startedAt: entry.startedAt, endedAt: entry.endedAt, title: entry.title,
                notes: entry.workoutNotes
            )
        }
        workouts[workoutKey]?.addSet(set, entry: entry)
    }

    /// Workouts in the order their first row appeared, each sorted internally by exercise's
    /// first-appearance order (set order within an exercise is preserved as-is).
    func finish() -> [ImportedWorkout] {
        order.compactMap { workouts[$0]?.finish() }
    }

    private struct WorkoutInProgress {
        var startedAt: Date
        var endedAt: Date?
        var title: String
        var notes: String
        private var exerciseOrder: [String] = []
        private var exercises: [String: ExerciseInProgress] = [:]

        init(startedAt: Date, endedAt: Date?, title: String, notes: String) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.title = title
            self.notes = notes
        }

        mutating func addSet(_ set: ImportedSet, entry: WorkoutRowInfo) {
            let name = entry.exerciseName
            if exercises[name] == nil {
                exerciseOrder.append(name)
                exercises[name] = ExerciseInProgress(name: name)
            }
            exercises[name]?.sets.append(set)
            if let existing = exercises[name], existing.note.isEmpty, !entry.exerciseNote.isEmpty {
                exercises[name]?.note = entry.exerciseNote
            }
            let current = exercises[name]
            if current?.category == nil, let category = entry.exerciseCategory {
                exercises[name]?.category = category
            }
            if current?.supersetGroup == nil, let group = entry.supersetGroup {
                exercises[name]?.supersetGroup = group
            }
        }

        func finish() -> ImportedWorkout {
            let entries = exerciseOrder.compactMap { exercises[$0] }.map {
                ImportedExercise(
                    name: $0.name, note: $0.note, category: $0.category,
                    supersetGroup: $0.supersetGroup, sets: $0.sets
                )
            }
            return ImportedWorkout(
                startedAt: startedAt, endedAt: endedAt, title: title, notes: notes, exercises: entries
            )
        }
    }

    private struct ExerciseInProgress {
        var name: String
        var note = ""
        var category: String?
        var supersetGroup: Int?
        var sets: [ImportedSet] = []
    }
}

/// The per-row workout/exercise context passed to `WorkoutBuilder.addSet`, grouped into one
/// value so the call site doesn't thread six separate parameters.
struct WorkoutRowInfo {
    var startedAt: Date
    var endedAt: Date?
    var title: String
    var workoutNotes: String
    var exerciseName: String
    var exerciseNote: String
    var exerciseCategory: String?
    var supersetGroup: Int?
}
