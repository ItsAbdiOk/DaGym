import Foundation
import SwiftData

/// One exercise performed inside a `WorkoutModel`, carrying its logged sets.
@Model
final class WorkoutExerciseModel {
    var id = UUID()
    var order: Int = 0
    var supersetGroup: Int?
    var note: String = ""
    var wasSubstitution: Bool = false
    /// True when this exercise was prescribed as part of a program's planned deload week
    /// (plan.md §6.5). Excluded as the baseline future progression builds from.
    var wasPlannedDeload: Bool = false
    /// True when the routine exercise this was logged under was flagged
    /// `RoutineExerciseModel.excludeFromProgression` at the time the workout was built — a
    /// rehab or accessory session that never becomes a progression baseline or ghost, even
    /// if the routine flag is edited later.
    var excludedFromProgression: Bool = false
    /// The routine this exercise was built from, stamped once when the row is first persisted
    /// (`WorkoutStore.sync(session:)`, mirroring `excludedFromProgression`) — a later edit to
    /// the routine, or the routine being deleted, leaves this workout's history as it was
    /// logged. Nil for a freestyle exercise or one with no routine slot. Lets a session built
    /// from more than one routine (`WorkoutStore.appendRoutine`) group its exercises in
    /// `WorkoutDetailView` and show the right routine's glyph on the rest-timer Live Activity.
    var routineID: UUID?

    @Relationship(inverse: \ExerciseModel.workoutExercises)
    var exercise: ExerciseModel?
    /// Inverse declared on `WorkoutModel.exercises`.
    var workout: WorkoutModel?
    @Relationship(deleteRule: .cascade, inverse: \SetLogModel.workoutExercise)
    var sets: [SetLogModel]?

    init(
        id: UUID = UUID(), order: Int = 0, supersetGroup: Int? = nil, note: String = "",
        wasSubstitution: Bool = false, wasPlannedDeload: Bool = false,
        excludedFromProgression: Bool = false, routineID: UUID? = nil,
        exercise: ExerciseModel? = nil, workout: WorkoutModel? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroup = supersetGroup
        self.note = note
        self.wasSubstitution = wasSubstitution
        self.wasPlannedDeload = wasPlannedDeload
        self.excludedFromProgression = excludedFromProgression
        self.routineID = routineID
        self.exercise = exercise
        self.workout = workout
    }
}
