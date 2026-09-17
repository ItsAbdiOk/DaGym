import Foundation

/// Identifies the one sheet presented over the workout at a time.
enum ActiveSheet: Identifiable {
    case keypad(exerciseID: UUID, setID: UUID, field: KeypadField)
    case effort(exerciseID: UUID, setID: UUID)
    case swap(entryID: UUID, exercise: ExerciseInfo)
    case addExercise
    case reorder
    case notes(exerciseID: UUID)
    case addRoutine
    /// The on-deck exercise's detail (its name or "Last 3" strip tapped).
    case exerciseDetail(ExerciseInfo)

    enum KeypadField: String {
        case weight, reps
        /// Cardio: minutes (decimal), distance in the display unit, incline %.
        case minutes, distance, incline
    }

    var id: String {
        switch self {
        case .keypad(let exerciseID, let setID, let field):
            "keypad-\(exerciseID)-\(setID)-\(field.rawValue)"
        case .effort(let exerciseID, let setID):
            "effort-\(exerciseID)-\(setID)"
        case .swap(let entryID, _):
            "swap-\(entryID)"
        case .addExercise:
            "add-exercise"
        case .reorder:
            "reorder"
        case .notes(let exerciseID):
            "notes-\(exerciseID)"
        case .addRoutine:
            "add-routine"
        case .exerciseDetail(let exercise):
            "exercise-\(exercise.id)"
        }
    }
}
