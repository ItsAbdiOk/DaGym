import Foundation
import GymCore

extension WorkoutStore {
    /// The muscle map's Strength mode: each primary mover's strongest exercises by cached best
    /// e1RM. Reads the exercise catalogue (one library fetch + one PR-cache fetch, both cached
    /// on `changeToken`), never a fetch per exercise.
    func muscleStrength(perMuscle: Int = 3) -> [Muscle: [MuscleStrength.Entry]] {
        let catalogue = exerciseCatalogue()
        let lifts = catalogue.models.compactMap { model -> MuscleStrength.Lift? in
            guard let best = catalogue.bestByExercise[model.id] else { return nil }
            return MuscleStrength.Lift(
                exerciseID: model.id, name: model.name, primary: model.primary, e1rmKg: best.value
            )
        }
        return MuscleStrength.top(lifts: lifts, perMuscle: perMuscle)
    }
}
