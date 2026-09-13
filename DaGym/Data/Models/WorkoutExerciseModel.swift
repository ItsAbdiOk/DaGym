import Foundation
import SwiftData

/// One exercise performed inside a `WorkoutModel`, carrying its logged sets.
@Model
final class WorkoutExerciseModel {
    var id: UUID = UUID()
    var order: Int = 0
    var supersetGroup: Int?
    var note: String = ""
    var wasSubstitution: Bool = false
    /// True when this exercise was prescribed as part of a program's planned deload week
    /// (plan.md §6.5). Excluded as the baseline future progression builds from.
    var wasPlannedDeload: Bool = false

    @Relationship(inverse: \ExerciseModel.workoutExercises)
    var exercise: ExerciseModel?
    /// Inverse declared on `WorkoutModel.exercises`.
    var workout: WorkoutModel?
    @Relationship(deleteRule: .cascade, inverse: \SetLogModel.workoutExercise)
    var sets: [SetLogModel]?

    init(
        id: UUID = UUID(), order: Int = 0, supersetGroup: Int? = nil, note: String = "",
        wasSubstitution: Bool = false, wasPlannedDeload: Bool = false,
        exercise: ExerciseModel? = nil, workout: WorkoutModel? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroup = supersetGroup
        self.note = note
        self.wasSubstitution = wasSubstitution
        self.wasPlannedDeload = wasPlannedDeload
        self.exercise = exercise
        self.workout = workout
    }
}
