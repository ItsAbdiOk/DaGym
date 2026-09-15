import Foundation
import SwiftData

/// One exercise slot inside a `RoutineModel`, carrying its planned sets.
@Model
final class RoutineExerciseModel {
    var id = UUID()
    var order: Int = 0
    /// Exercises sharing a group id are a superset.
    var supersetGroup: Int?
    var restOverrideSeconds: Int?
    var note: String = ""
    /// JSON-encoded `GymCore.ProgressionRule` override for this exercise; nil defers to the
    /// routine's rule (plan.md §6.5).
    var progressionRuleJSON: String?
    /// JSON-encoded `GymCore.StallState` (miss streak + last weight), persisted when a workout
    /// using this exercise finishes.
    var stallJSON: String = "{}"
    /// Rolling training max for `.percentOfTrainingMax`, persisted on finish.
    var trainingMaxKg: Double?
    /// Planned deloads: excluded from auto-progression (the exercise repeats/stays as planned
    /// rather than being driven by the engine).
    var excludeFromProgression: Bool = false

    @Relationship(inverse: \ExerciseModel.routineExercises)
    var exercise: ExerciseModel?
    /// Inverse declared on `RoutineModel.exercises`.
    var routine: RoutineModel?
    @Relationship(deleteRule: .cascade, inverse: \PlannedSetModel.routineExercise)
    var plannedSets: [PlannedSetModel]?

    init(
        id: UUID = UUID(), order: Int = 0, supersetGroup: Int? = nil,
        restOverrideSeconds: Int? = nil, note: String = "", progressionRuleJSON: String? = nil,
        stallJSON: String = "{}", trainingMaxKg: Double? = nil, excludeFromProgression: Bool = false,
        exercise: ExerciseModel? = nil, routine: RoutineModel? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroup = supersetGroup
        self.restOverrideSeconds = restOverrideSeconds
        self.note = note
        self.progressionRuleJSON = progressionRuleJSON
        self.stallJSON = stallJSON
        self.trainingMaxKg = trainingMaxKg
        self.excludeFromProgression = excludeFromProgression
        self.exercise = exercise
        self.routine = routine
    }
}
