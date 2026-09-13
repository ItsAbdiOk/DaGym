import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// Ends the session, computes PRs against the cache and returns a summary. Backfilled or
    /// otherwise earlier-dated workouts never claim a PR against a later-dated one.
    func finish(session: WorkoutSession) -> WorkoutSummary {
        sync(session: session)
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID) else {
            return WorkoutSummary(durationSeconds: 0, volumeKg: 0, setsDone: 0, prs: [], musclesHit: [:])
        }
        let endedAt = Date()
        workout.endedAt = endedAt
        let prs = evaluatePRs(session: session, workout: workout)
        save()
        return WorkoutSummary(
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(workout.startedAt))),
            volumeKg: session.volumeKg, setsDone: session.setsDone, prs: prs, musclesHit: session.musclesHit
        )
    }

    func history() -> [WorkoutRecord] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map { WorkoutRecord(model: $0, prCount: prCount(for: $0.id)) }
    }

    func workout(id: UUID) -> WorkoutModel? {
        fetchWorkoutModel(id: id)
    }

    func deleteWorkout(id: UUID) {
        guard let model = fetchWorkoutModel(id: id) else { return }
        context.delete(model)
        save()
    }

    /// "80 × 8,8,7" style lines for the last few finished sessions of an exercise.
    func lastSessions(exerciseID: UUID, limit: Int = 3) -> [String] {
        var lines: [String] = []
        for workout in finishedWorkoutsNewestFirst() {
            guard let line = sessionLine(exerciseID: exerciseID, in: workout) else { continue }
            lines.append(line)
            if lines.count == limit { break }
        }
        return lines
    }

    /// e1RM per finished workout that included this exercise, oldest first, for the sparkline.
    func e1rmSeries(exerciseID: UUID) -> [(Date, Double)] {
        finishedWorkoutsNewestFirst().reversed().compactMap { workout in
            bestE1RM(exerciseID: exerciseID, in: workout).map { (workout.startedAt, $0) }
        }
    }

    // MARK: - Helpers

    private func finishedWorkoutsNewestFirst() -> [WorkoutModel] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func sessionLine(exerciseID: UUID, in workout: WorkoutModel) -> String? {
        guard let match = matchingExercise(exerciseID: exerciseID, in: workout) else { return nil }
        let sets = (match.sets ?? [])
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .sorted { $0.order < $1.order }
        guard let first = sets.first else { return nil }
        let reps = sets.map { String($0.reps) }.joined(separator: ",")
        return "\(WorkoutSession.format(first.weightKg)) × \(reps)"
    }

    private func bestE1RM(exerciseID: UUID, in workout: WorkoutModel) -> Double? {
        guard let match = matchingExercise(exerciseID: exerciseID, in: workout) else { return nil }
        return (match.sets ?? [])
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }
            .max()
    }

    private func matchingExercise(exerciseID: UUID, in workout: WorkoutModel) -> WorkoutExerciseModel? {
        (workout.exercises ?? []).first { $0.exercise?.id == exerciseID }
    }

    private func prCount(for workoutID: UUID) -> Int {
        let predicate = #Predicate<PersonalRecordModel> { $0.workoutID == workoutID }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    /// The best eligible set (highest e1RM) inside one exercise entry.
    private struct BestSet {
        var weightKg: Double
        var reps: Int
        var value: Double
    }

    /// A PR candidate ready to compare against the cache.
    private struct PRCandidate {
        var exerciseID: UUID
        var exerciseName: String
        var best: BestSet
        var date: Date
        var workoutID: UUID
    }

    /// Swap for `GymCore.PersonalRecords.evaluate` once the shared module lands (lead's note).
    private func evaluatePRs(session: WorkoutSession, workout: WorkoutModel) -> [PersonalRecordInfo] {
        session.exercises.compactMap { entry -> PersonalRecordInfo? in
            guard let best = bestEligibleSet(in: entry) else { return nil }
            let candidate = PRCandidate(
                exerciseID: entry.exercise.id, exerciseName: entry.exercise.name, best: best,
                date: workout.startedAt, workoutID: workout.id
            )
            return recordE1RMIfBest(candidate)
        }
    }

    private func bestEligibleSet(in entry: WorkoutExerciseEntry) -> BestSet? {
        var best: BestSet?
        for setEntry in entry.sets where setEntry.isDone && setEntry.kind.countsTowardStats {
            guard let value = OneRepMax.estimate(weight: setEntry.weightKg, reps: setEntry.reps) else {
                continue
            }
            if value > (best?.value ?? 0) {
                best = BestSet(weightKg: setEntry.weightKg, reps: setEntry.reps, value: value)
            }
        }
        return best
    }

    private func recordE1RMIfBest(_ candidate: PRCandidate) -> PersonalRecordInfo? {
        let exerciseID = candidate.exerciseID
        let predicate = #Predicate<PersonalRecordModel> { $0.exerciseID == exerciseID && $0.kind == "e1rm" }
        let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first
        if let existing, candidate.date < existing.date { return nil }
        guard candidate.best.value > (existing?.value ?? 0) else { return nil }
        let record = existing ?? PersonalRecordModel(exerciseID: exerciseID, kind: "e1rm")
        if existing == nil { context.insert(record) }
        record.value = candidate.best.value
        record.weightKg = candidate.best.weightKg
        record.reps = candidate.best.reps
        record.date = candidate.date
        record.workoutID = candidate.workoutID
        let weight = WorkoutSession.format(candidate.best.weightKg)
        let value = WorkoutSession.format(candidate.best.value)
        let line = "\(weight) × \(candidate.best.reps) → \(value) kg e1RM"
        return PersonalRecordInfo(exerciseName: candidate.exerciseName, line: line)
    }
}
