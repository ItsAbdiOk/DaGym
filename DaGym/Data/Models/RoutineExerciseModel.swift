import Foundation
import SwiftData

/// One exercise slot inside a `RoutineModel`, carrying its planned sets.
@Model
final class RoutineExerciseModel {
    var id: UUID = UUID()
    var order: Int = 0
    /// Exercises sharing a group id are a superset.
    var supersetGroup: Int?
    var restOverrideSeconds: Int?
    var note: String = ""

    @Relationship(inverse: \ExerciseModel.routineExercises)
    var exercise: ExerciseModel?
    /// Inverse declared on `RoutineModel.exercises`.
    var routine: RoutineModel?
    @Relationship(deleteRule: .cascade, inverse: \PlannedSetModel.routineExercise)
    var plannedSets: [PlannedSetModel]?

    init(
        id: UUID = UUID(), order: Int = 0, supersetGroup: Int? = nil,
        restOverrideSeconds: Int? = nil, note: String = "", exercise: ExerciseModel? = nil,
        routine: RoutineModel? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroup = supersetGroup
        self.restOverrideSeconds = restOverrideSeconds
        self.note = note
        self.exercise = exercise
        self.routine = routine
    }
}
