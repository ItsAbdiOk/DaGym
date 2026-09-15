import Foundation
import GymCore
import SwiftData

/// Per-exercise reads over finished history: the "last sessions" lines and the sparkline the
/// exercise card shows, and the set-matching helper everything in this area shares.
extension WorkoutStore {
    /// "80 × 8,8,7" style lines for the last few finished sessions of an exercise — "0:45, 0:40"
    /// for a timed hold, "12, 12, 10" for unloaded reps (see `sessionLine`). Pass
    /// `finishedWorkouts` (newest first) to reuse an already-fetched list instead of querying
    /// the store again.
    /// `style`, when passed, is used as-is instead of re-fetching the `ExerciseModel` just to
    /// read it — a caller holding the `ExerciseInfo` already has it (`ExerciseInfo.loggingStyle`
    /// *is* `ExerciseModel.style`; the `.weightReps` default matches the deleted-exercise case).
    func lastSessions(
        exerciseID: UUID, limit: Int = 3, finishedWorkouts: [WorkoutModel]? = nil,
        style: ExerciseInfo.LoggingStyle? = nil
    ) -> [String] {
        let style = style ?? fetchExerciseModel(id: exerciseID)?.style ?? .weightReps
        var lines: [String] = []
        for workout in finishedWorkouts ?? finishedWorkoutModelsNewestFirst() {
            guard let line = sessionLine(exerciseID: exerciseID, style: style, in: workout) else { continue }
            lines.append(line)
            if lines.count == limit { break }
        }
        return lines
    }

    /// e1RM per finished workout that included this exercise, oldest first, for the sparkline.
    /// Pass `finishedWorkouts` (newest first) to reuse an already-fetched list.
    func e1rmSeries(exerciseID: UUID, finishedWorkouts: [WorkoutModel]? = nil) -> [(Date, Double)] {
        (finishedWorkouts ?? finishedWorkoutModelsNewestFirst()).reversed().compactMap { workout in
            bestE1RM(exerciseID: exerciseID, in: workout).map { (workout.startedAt, $0) }
        }
    }

    /// The card sparkline's per-session value, oldest first, by how the exercise is logged:
    /// best hold for a timed exercise, best reps for unloaded reps, else best e1RM. Pass
    /// `finishedWorkouts` (newest first) to reuse an already-fetched list, and `style` to skip
    /// the `ExerciseModel` fetch that only reads it (see `lastSessions`).
    func sparklineSeries(
        exerciseID: UUID, finishedWorkouts: [WorkoutModel]? = nil,
        style: ExerciseInfo.LoggingStyle? = nil
    ) -> [(Date, Double)] {
        let best: ((SetLogModel) -> Double)?
        switch style ?? fetchExerciseModel(id: exerciseID)?.style ?? .weightReps {
        case .timedHold: best = { Double($0.durationSeconds ?? 0) }
        case .cardio: best = cardioSparklineValue(exerciseID: exerciseID, finishedWorkouts: finishedWorkouts)
        case .bodyweightReps: best = { Double($0.reps) }
        case .weightReps, .assisted, .weightedBodyweight: best = nil
        }
        guard let best else {
            return e1rmSeries(exerciseID: exerciseID, finishedWorkouts: finishedWorkouts)
        }
        return bestPerSession(exerciseID: exerciseID, finishedWorkouts: finishedWorkouts, value: best)
    }

    private func bestPerSession(
        exerciseID: UUID, finishedWorkouts: [WorkoutModel]? = nil, value: (SetLogModel) -> Double
    ) -> [(Date, Double)] {
        (finishedWorkouts ?? finishedWorkoutModelsNewestFirst()).reversed().compactMap { workout in
            guard let match = matchingSets(exerciseID: exerciseID, in: workout) else { return nil }
            let best = match
                .filter { $0.isCompleted && $0.setKind.countsTowardStats }
                .map(value).max()
            return best.map { (workout.startedAt, $0) }
        }
    }

    // MARK: - Helpers

    private func sessionLine(
        exerciseID: UUID, style: ExerciseInfo.LoggingStyle, in workout: WorkoutModel
    ) -> String? {
        guard let match = matchingSets(exerciseID: exerciseID, in: workout) else { return nil }
        let sets = match.filter { $0.isCompleted && $0.setKind.countsTowardStats }
        guard let first = sets.first else { return nil }
        switch style {
        case .timedHold:
            return sets.map { WorkoutSession.clock($0.durationSeconds ?? 0) }.joined(separator: ", ")
        case .cardio:
            return cardioSessionLine(sets: sets, unit: preferredDistanceUnit)
        case .bodyweightReps:
            return sets.map { String($0.reps) }.joined(separator: ", ")
        case .weightReps, .assisted, .weightedBodyweight:
            let reps = sets.map { String($0.reps) }.joined(separator: ",")
            return "\(WorkoutSession.format(first.weightKg)) × \(reps)"
        }
    }

    /// The best estimated 1RM over this exercise's counting sets in one workout, nil when the
    /// workout didn't include it. Shared by the sparkline and the summary's "vs last time".
    func bestE1RM(exerciseID: UUID, in workout: WorkoutModel) -> Double? {
        guard let match = matchingSets(exerciseID: exerciseID, in: workout) else { return nil }
        return match
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }
            .max()
    }

    /// Every logged row for `exerciseID` in this workout, in logged order — nil when the workout
    /// doesn't contain the exercise at all.
    ///
    /// It used to take `.first`, so an exercise logged twice in one session (bench 80 × 8 early,
    /// bench 100 × 3 at the end) was half-invisible: the history line, the card sparkline and
    /// the exercise's best-e1RM all read the first entry and never saw the heavier one.
    func matchingSets(exerciseID: UUID, in workout: WorkoutModel) -> [SetLogModel]? {
        let matches = (workout.exercises ?? [])
            .filter { $0.exercise?.id == exerciseID }
            .sorted { $0.order < $1.order }
        guard !matches.isEmpty else { return nil }
        return matches.flatMap { ($0.sets ?? []).sorted { $0.order < $1.order } }
    }
}
