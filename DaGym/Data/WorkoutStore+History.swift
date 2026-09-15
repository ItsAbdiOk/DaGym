import Foundation
import GymCore
import SwiftData

/// Finishing a session: `finish(session:)` and the summary it returns. The rest of the history
/// API is split by concern — reads in `WorkoutStore+HistoryReads.swift`, delete/undo in
/// `WorkoutStore+WorkoutDeletion.swift`, per-exercise lines and series in
/// `WorkoutStore+ExerciseSeries.swift`.
extension WorkoutStore {
    /// Ends the session, computes PRs against the cache and returns a summary. Backfilled or
    /// otherwise earlier-dated workouts never claim a PR against a later-dated one.
    /// `weeklyGoal` (`Preferences.weeklyGoal`) and `calendar` (`Preferences.trainingCalendar`,
    /// whose `firstWeekday` defines "this week") feed the streak/consistency milestones; both
    /// are additive with defaults so existing call sites compile unchanged.
    func finish(
        session: WorkoutSession, weeklyGoal: Int = 4, calendar: Calendar = .current, unit: WeightUnit = .kg
    ) -> WorkoutSummary {
        let state = storeSignposter.beginInterval("finish")
        defer { storeSignposter.endInterval("finish", state) }
        sync(session: session)
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID) else {
            return WorkoutSummary(durationSeconds: 0, volumeKg: 0, setsDone: 0, prs: [], musclesHit: [:])
        }
        // The finished-workout list, read once for everything below — progression's baseline,
        // the PR date guard, the milestone numbers, the "vs last time" workout and the debrief.
        // Each used to fetch it again (eight table reads per finish, growing with history).
        // Read before `endedAt` is stamped, so this session is not in it.
        let finished = finishedWorkoutModelsNewestFirst().filter { $0.id != workout.id }
        // A session is finished exactly once: a second call (double-tap, re-entrant sheet) would
        // otherwise re-run progression with this session now inside its own baseline and burn a
        // second stall. A backfill used to be exempt from this guard, because `startBackfill`
        // stamped its `endedAt` up front and there was no other way to tell it from a finished
        // one; it no longer does, so `endedAt` alone is the answer for every session.
        if workout.endedAt != nil {
            return summary(
                for: workout, session: session, prs: [], achievements: [], finishedWorkouts: finished
            )
        }
        // Computed with this session still excluded from `exerciseHistory` (its own `endedAt`
        // isn't stamped until after this) — the exact same baseline/stall `startWorkout` used to
        // prescribe this session, so this simply commits that already-shown result. Persisting
        // here rather than at start means abandoning a workout (never finishing) never burns a
        // stall (plan.md §6.5).
        persistProgression(session: session, workout: workout, finishedWorkouts: finished)
        pruneUnfinishedRows(of: workout)
        let now = Date()
        let endedAt = Self.endDate(for: workout, session: session, now: now)
        workout.endedAt = endedAt
        // The sets were stamped before the workout had an end; re-clamp them into the window it
        // has now, so `completedAt` always lands inside `[startedAt, endedAt]` (which is what
        // recovery decays from).
        for setModel in (workout.exercises ?? []).flatMap({ $0.sets ?? [] }) {
            guard let completedAt = setModel.completedAt else { continue }
            setModel.completedAt = Self.completionDate(completedAt, in: workout)
        }
        // The persisted totals History and the lifetime header read (see `WorkoutModel.stampTotals`).
        workout.stampTotals()
        let prs = evaluatePRs(session: session, workout: workout, unit: unit, finishedWorkouts: finished)
        // Finished now, so the milestone numbers count this session too.
        let earnedAchievements = evaluateMilestones(
            for: workout, weeklyGoal: weeklyGoal, calendar: calendar, unit: unit,
            finishedWorkouts: Self.inserting(workout, into: finished)
        )
        // Backfilled/past-dated workouts still earn milestones (persisted above) but never
        // celebrate — the summary card only shows the ones worth celebrating right now.
        let achievements = Milestones.isCelebrationWorthy(workoutDate: workout.startedAt, now: now)
            ? earnedAchievements : []
        save()
        onWorkoutFinished?(workout)
        workoutFinishedObservers.forEach { $0(workout) }
        WidgetSnapshotWriter.refresh(store: self)
        return summary(
            for: workout, session: session, prs: prs, achievements: achievements, finishedWorkouts: finished
        )
    }

    /// `workout` slotted into a newest-first list at its date — the list as a fresh fetch would
    /// return it now that the workout is finished.
    private static func inserting(_ workout: WorkoutModel, into finished: [WorkoutModel]) -> [WorkoutModel] {
        let index = finished.firstIndex { $0.startedAt <= workout.startedAt } ?? finished.endIndex
        var all = finished
        all.insert(workout, at: index)
        return all
    }

    /// History only ever holds what was actually done: an unticked planned row, and an exercise
    /// left with no rows, are dropped here — in `finish`, not `sync`, so an in-progress session
    /// keeps its planned rows for resume. The `WorkoutModel` itself stays even when it empties.
    ///
    /// A pruned exercise's *note* survives onto the workout's own notes. "Skipped, left shoulder
    /// pinching" is exactly the note worth keeping, and it was thrown away with the row.
    private func pruneUnfinishedRows(of workout: WorkoutModel) {
        for exerciseModel in workout.exercises ?? [] {
            for setModel in (exerciseModel.sets ?? []).filter({ !$0.isCompleted }) {
                context.delete(setModel)
            }
        }
        let emptied = (workout.exercises ?? []).filter { ($0.sets ?? []).allSatisfy { !$0.isCompleted } }
        let rescued = emptied.compactMap { exerciseModel -> String? in
            let note = exerciseModel.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return nil }
            let name = exerciseModel.exercise?.name ?? "Exercise"
            return "Skipped \(name): \(note)"
        }
        if !rescued.isEmpty {
            workout.notes = ([workout.notes] + rescued)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        // Deleted through the context alone: re-assigning the parent's array while SwiftData is
        // mid-way through updating that same relationship traps.
        emptied.forEach(context.delete)
    }

    private func summary(
        for workout: WorkoutModel, session: WorkoutSession, prs: [PersonalRecordInfo],
        achievements: [AchievementInfo], finishedWorkouts: [WorkoutModel]
    ) -> WorkoutSummary {
        let endedAt = workout.endedAt ?? Date()
        // Working sets only, the same count the History row and the weekly recap show.
        let setsDone = session.exercises.flatMap(\.sets)
            .filter { $0.isDone && $0.kind.countsTowardStats }.count
        let previous = Self.previousWorkout(before: workout, in: finishedWorkouts)
        var summary = WorkoutSummary(
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(workout.startedAt))),
            volumeKg: session.volumeKg, setsDone: setsDone, prs: prs, musclesHit: session.musclesHit,
            achievements: achievements, previous: previous.map(previousWorkoutSummary),
            e1rmChanges: e1rmChanges(session: session, previous: previous),
            distanceMeters: session.distanceMeters
        )
        summary.debriefFacts = debriefFacts(session: session, summary: summary, previous: previous)
        return summary
    }

    /// The latest finished workout on the same routine — same title when neither has a routine
    /// — started before this one. "Before its own date", not "newest overall", so a backfill
    /// compares against what came before it.
    private static func previousWorkout(
        before workout: WorkoutModel, in finished: [WorkoutModel]
    ) -> WorkoutModel? {
        finished.first { candidate in
            guard candidate.id != workout.id, candidate.startedAt < workout.startedAt else { return false }
            if let routineID = workout.routineID { return candidate.routineID == routineID }
            return candidate.routineID == nil && candidate.title == workout.title
        }
    }

    private func previousWorkoutSummary(_ workout: WorkoutModel) -> PreviousWorkoutSummary {
        let endedAt = workout.endedAt ?? workout.startedAt
        let stamped = workout.hasStampedTotals
        return PreviousWorkoutSummary(
            workoutID: workout.id, date: workout.startedAt,
            volumeKg: stamped ? workout.volumeKg : workout.loadedVolumeKg,
            setsDone: stamped ? workout.setsDone : workout.loadedSetsDone,
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(workout.startedAt))),
            prCount: prCount(for: workout.id)
        )
    }

    /// One row per exercise, merging every entry for it in the session.
    ///
    /// The same exercise can legitimately appear twice in one workout — bench 80 × 8 early, bench
    /// again at 100 × 3 at the end. A `seen` guard emitted the first entry and dropped the second
    /// entry's sets entirely, so the summary reported the 80 × 8 as the session's best while the
    /// PR banner right above it celebrated the 100 × 3.
    private func e1rmChanges(session: WorkoutSession, previous: WorkoutModel?) -> [ExerciseE1RMChange] {
        var order: [UUID] = []
        var setsByExercise: [UUID: [SetEntry]] = [:]
        var names: [UUID: String] = [:]
        for entry in session.exercises {
            if setsByExercise[entry.exercise.id] == nil {
                order.append(entry.exercise.id)
                names[entry.exercise.id] = entry.exercise.name
            }
            setsByExercise[entry.exercise.id, default: []] += entry.sets
        }
        return order.compactMap { exerciseID in
            let current = (setsByExercise[exerciseID] ?? [])
                .filter { $0.isDone && $0.kind.countsTowardStats }
                .compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }
                .max()
            let before = previous.flatMap { bestE1RM(exerciseID: exerciseID, in: $0) }
            guard current != nil || before != nil else { return nil }
            return ExerciseE1RMChange(
                exerciseID: exerciseID, name: names[exerciseID] ?? "", previous: before, current: current
            )
        }
    }
}
