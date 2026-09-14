import Foundation
import GymCore
import SwiftData

/// The cardio slice of the store (plan.md §6.1): what a run row is pre-filled with, and how a
/// run reads back in the last-sessions strip and sparkline. Cardio never goes through the
/// progression engine — there is no load to step — so the prescription is the previous session
/// verbatim, or the plan's targets the first time.
extension WorkoutStore {
    /// A planned cardio set as the entry builder needs it: `PlannedSetModel` minus SwiftData.
    struct CardioPlan {
        var kind: SetKind = .working
        var targetSeconds: Int?
        var targetDistanceMeters: Double?

        init(kind: SetKind = .working, targetSeconds: Int? = nil, targetDistanceMeters: Double? = nil) {
            self.kind = kind
            self.targetSeconds = targetSeconds
            self.targetDistanceMeters = targetDistanceMeters
        }

        init(model: PlannedSetModel) {
            self.init(
                kind: model.setKind, targetSeconds: model.targetSeconds,
                targetDistanceMeters: model.targetDistanceMeters
            )
        }
    }

    /// One cardio set from the previous session, position-matched by kind like `AutoFill`.
    struct PreviousCardioSet {
        var kind: SetKind
        var seconds: Int?
        var meters: Double?
        var inclinePercent: Double?
    }

    /// The previous counting session's completed cardio sets for `exerciseID`, in order.
    func previousCardioSets(exerciseID: UUID, finishedWorkouts: [WorkoutModel]?) -> [PreviousCardioSet] {
        guard let previous = previousLoggedExercise(
            exerciseID: exerciseID, finishedWorkouts: finishedWorkouts
        ) else { return [] }
        return (previous.exercise.sets ?? []).filter(\.isCompleted).sorted { $0.order < $1.order }
            .map {
                PreviousCardioSet(
                    kind: $0.setKind, seconds: $0.durationSeconds, meters: $0.distanceMeters,
                    inclinePercent: $0.inclinePercent
                )
            }
    }

    /// The entry for a cardio routine slot: each planned set carries last session's time and
    /// distance as its targets (the plan's own targets when there is no last session), and the
    /// why card says which it was. A planned deload week changes nothing here — a run has no
    /// load to back off.
    func cardioEntry(
        info: ExerciseInfo, planned: [CardioPlan], routineExercise: RoutineExerciseModel?,
        finishedWorkouts: [WorkoutModel]?, unit: DistanceUnit
    ) -> WorkoutExerciseEntry {
        let previous = previousCardioSets(exerciseID: info.id, finishedWorkouts: finishedWorkouts)
        var seenByKind: [SetKind: Int] = [:]
        let sets = planned.map { plan -> SetEntry in
            let position = seenByKind[plan.kind, default: 0]
            seenByKind[plan.kind] = position + 1
            let matches = previous.filter { $0.kind == plan.kind }
            let match = matches.indices.contains(position) ? matches[position] : matches.last
            return SetEntry(
                kind: plan.kind, weightKg: 0, reps: 0,
                targetSeconds: match?.seconds ?? plan.targetSeconds,
                prescriptionReason: match == nil ? "From your plan" : "Same as last time",
                targetDistanceMeters: match?.meters ?? plan.targetDistanceMeters,
                inclinePercent: match?.inclinePercent
            )
        }
        let reason = Self.cardioReason(previous: previous, unit: unit)
        return WorkoutExerciseEntry(
            exercise: info, sets: sets, supersetGroup: routineExercise?.supersetGroup,
            note: (routineExercise?.note).flatMap { $0.isEmpty ? nil : $0 },
            whyTitle: reason.title, whyBody: reason.body, whyKind: reason.kind
        )
    }

    /// `cardioEntry` for a routine slot, fed from the session's shared facts.
    func cardioEntry(
        info: ExerciseInfo, plannedSets: [PlannedSetModel], routineExercise: RoutineExerciseModel,
        facts: SessionFacts
    ) -> WorkoutExerciseEntry {
        cardioEntry(
            info: info, planned: plannedSets.map(CardioPlan.init(model:)), routineExercise: routineExercise,
            finishedWorkouts: facts.finishedWorkouts, unit: preferredDistanceUnit
        )
    }

    /// A run added mid-workout: one row per set logged last time (or one blank row), each
    /// pre-filled from that session — never three "0 × 0" rows.
    func cardioAddedEntry(
        for exercise: ExerciseInfo, setCount: Int?, facts: SessionFacts
    ) -> WorkoutExerciseEntry {
        let finished = facts.finishedWorkouts
        let previousCount = previousCardioSets(exerciseID: exercise.id, finishedWorkouts: finished).count
        let rows = Array(repeating: CardioPlan(), count: max(1, setCount ?? previousCount))
        return cardioEntry(
            info: exercise, planned: rows, routineExercise: nil, finishedWorkouts: finished,
            unit: preferredDistanceUnit
        )
    }

    /// "Same as last time — 5.00 km · 25:30 · 5:06 /km. Match it or go a little further."
    static func cardioReason(previous: [PreviousCardioSet], unit: DistanceUnit) -> PrescriptionReason {
        let longest = previous.max { ($0.meters ?? 0, $0.seconds ?? 0) < ($1.meters ?? 0, $1.seconds ?? 0) }
        guard let best = longest else {
            return PrescriptionReason(
                title: "From your plan", body: "No run logged yet — the targets are the plan's.",
                kind: .firstTime
            )
        }
        let line = SetEntry(
            weightKg: 0, reps: 0, durationSeconds: best.seconds, distanceMeters: best.meters
        ).cardioSummary(unit: unit)
        return PrescriptionReason(
            title: "Same as last time",
            body: "Last session: \(line). Match it, or go a little further or faster.",
            kind: .repeat
        )
    }

    /// The last-sessions strip line for a cardio exercise: one "5.00 km · 25:30" per set.
    func cardioSessionLine(sets: [SetLogModel], unit: DistanceUnit) -> String {
        sets.map { set in
            SetEntry(
                weightKg: 0, reps: 0, durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters
            ).cardioSummary(unit: unit)
        }
        .joined(separator: ", ")
    }

    /// The sparkline value for one cardio set: metres when the exercise has ever logged a
    /// distance, seconds otherwise — a treadmill user sees distance climb, a rower who only
    /// logs time sees time.
    func cardioSparklineValue(
        exerciseID: UUID, finishedWorkouts: [WorkoutModel]?
    ) -> (SetLogModel) -> Double {
        let hasDistance = (finishedWorkouts ?? finishedWorkoutModelsNewestFirst()).contains { workout in
            (matchingSets(exerciseID: exerciseID, in: workout) ?? [])
                .contains { ($0.distanceMeters ?? 0) > 0 }
        }
        return hasDistance ? { $0.distanceMeters ?? 0 } : { Double($0.durationSeconds ?? 0) }
    }

    /// The distance unit the store formats cardio in — `Preferences` is UI state, so the store
    /// reads the same key directly, the way `preferredWeightUnit` does for kg/lb.
    var preferredDistanceUnit: DistanceUnit {
        DistanceUnit(rawValue: UserDefaults.standard.string(forKey: Preferences.Key.distanceUnit) ?? "")
            ?? DistanceUnit.matching(preferredWeightUnit)
    }
}
