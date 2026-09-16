import Foundation
import GymCore
import SwiftData

/// The read side of history: the History list and header, resume/purge of unfinished sessions,
/// the detail screen and the date list every streak is computed from. `finish` lives in
/// `WorkoutStore+History.swift`.
extension WorkoutStore {
    /// In-progress (never finished, never discarded) workouts, newest first — what a crash or
    /// force-quit mid-session leaves behind. The launch flow offers to resume the newest via
    /// `resumeSession(for:)` and purges the rest with `purgeUnfinished(olderThan:)`.
    func unfinishedWorkouts() -> [WorkoutModel] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt == nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return fetch(descriptor)
    }

    /// Clears out unfinished workouts started before `date`, **without ever destroying logged
    /// work**. Returns how many were dealt with.
    ///
    /// This runs at launch, before the user is asked anything. It used to delete outright, so a
    /// Friday session with 14 sets in it was silently gone by Sunday — no prompt, no undo — and
    /// on a CloudKit-mirrored store it could delete a workout another device was still logging.
    /// A workout with completed sets is now auto-finished instead, at its own last logged set
    /// (see `endDate(for:session:now:)`), which is what the lifter would have got had they
    /// remembered to tap Finish. Only a genuinely empty shell is deleted.
    @discardableResult
    func purgeUnfinished(olderThan date: Date) -> Int {
        let stale = unfinishedWorkouts().filter { $0.startedAt < date }
        guard !stale.isEmpty else { return 0 }
        for workout in stale {
            let hasLoggedWork = (workout.exercises ?? [])
                .flatMap { $0.sets ?? [] }
                .contains(where: \.isCompleted)
            if hasLoggedWork, let session = resumeSession(for: workout.id) {
                _ = finish(session: session)
            } else {
                context.delete(workout)
            }
        }
        save()
        return stale.count
    }

    /// Re-opens an unfinished workout as a live `WorkoutSession` so `ActiveWorkoutView` can carry
    /// on where it stopped. Nil once the workout has been finished or deleted.
    ///
    /// Everything the session carries that `sync` does not persist is rebuilt here, because a
    /// resumed workout is meant to be indistinguishable from the one that was interrupted: the
    /// history strip and sparkline, the per-set ghost of the previous session (`withGhosts`), and
    /// the "already logged once" set of ids that stops a re-tick restarting rest
    /// (`markLoggedSetsAsSeen`). The "why" headline comes back from the per-set
    /// `prescriptionReason` the store *does* persist (see `WorkoutExerciseEntry.init(model:)`),
    /// and a timed hold's target from its uncompleted row's duration.
    func resumeSession(for workoutID: UUID) -> WorkoutSession? {
        guard let model = fetchWorkoutModel(id: workoutID), model.endedAt == nil else { return nil }
        // Fetched once and shared: every exercise's `exerciseInfo` stats and history strip would
        // otherwise re-query the finished-workout list, the PR cache and its own `ExerciseModel`.
        let facts = makeSessionFacts(routineID: model.routineID)
        let session = WorkoutSession(model: model, exerciseInfo: { self.exerciseInfo(for: $0, facts: facts) })
        session.exercises = session.exercises.map {
            withGhosts(withHistoryStrip($0, facts: facts), facts: facts)
        }
        session.routineGlyphs = routineGlyphs(for: session.exercises)
        session.markLoggedSetsAsSeen()
        return session
    }

    /// Everything finished, newest first: the main store's own workouts plus whatever was
    /// imported from Apple Health, which lives in the separate always-local Health store (see
    /// `WorkoutStore+HealthImport.swift`). Merged here so History stays one list and no caller
    /// has to know where a row came from.
    ///
    /// Three queries however long the history: the workouts (with their exercise rows
    /// prefetched), the headline PR events grouped by workout, and the Health imports. It was
    /// one `fetchCount` per workout for the PR badge, plus a relationship fault per row.
    func history() -> [WorkoutRecord] {
        let state = storeSignposter.beginInterval("history")
        defer { storeSignposter.endInterval("history", state) }
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        var descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]
        let models = fetch(descriptor)
        let prCounts = prCountsByWorkout()
        let own = models.map { WorkoutRecord(model: $0, prCount: prCounts[$0.id] ?? 0) }
        let imported = importedHealthWorkouts().map(Self.record(imported:))
        return (own + imported).sorted { $0.date > $1.date }
    }

    func workout(id: UUID) -> WorkoutModel? {
        fetchWorkoutModel(id: id)
    }

    /// Total finished-workout count and lifetime volume, for the History header.
    ///
    /// A sum over the stamped `WorkoutModel.volumeKg` column (see `stampTotals`), so it no
    /// longer faults every set ever logged — which it did on every `finish` and every History
    /// visit, through `milestoneState`. Pass `finishedWorkouts` (newest first) to sum a list
    /// already in hand.
    func lifetimeStats(finishedWorkouts: [WorkoutModel]? = nil) -> (workouts: Int, volumeKg: Double) {
        let finished: [WorkoutModel]
        if let finishedWorkouts {
            finished = finishedWorkouts
        } else {
            var descriptor = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.endedAt != nil })
            descriptor.propertiesToFetch = [\.volumeKg, \.setsDone]
            finished = fetch(descriptor)
        }
        let volume = finished.reduce(0.0) { total, workout in
            // A zero row is either empty or was never stamped; recomputing an empty one is free.
            total + (workout.hasStampedTotals ? workout.volumeKg : workout.loadedVolumeKg)
        }
        // Imported Apple Health sessions count as workouts done; they carry no volume.
        return (finished.count + importedHealthWorkouts().count, volume)
    }

    /// One-shot, run from the launch seeding pass (a read never writes): stamps `volumeKg`/
    /// `setsDone` on every finished workout that predates those columns, then records the pass
    /// on `SeedStateModel` so it never runs again. One query (the seed row) on a store that has
    /// already run it; a full walk of history exactly once.
    func backfillWorkoutTotalsIfNeeded() {
        let seedState = SeedState.row(in: self)
        guard !seedState.workoutTotalsBackfilled else { return }
        for workout in finishedWorkoutModelsNewestFirst() where !workout.hasStampedTotals {
            workout.stampTotals()
        }
        seedState.workoutTotalsBackfilled = true
        seedState.updatedAt = Date()
        save()
    }

    /// Re-stamps any finished workout whose persisted totals disagree with its rows. CloudKit
    /// delivers record types in batches, so a workout can arrive (and be stamped by the one-shot
    /// backfill, or by an older build's device) before all of its sets have — and a stamp that
    /// is merely *wrong* is never retried by `hasStampedTotals`. Called from the remote-change
    /// quiet pass; it walks history's sets once per burst, which is what History used to do on
    /// every visit. Returns the number of rows corrected.
    @discardableResult
    func restampWorkoutTotalsAfterRemoteChange() -> Int {
        var corrected = 0
        for workout in finishedWorkoutModelsNewestFirst()
        where workout.setsDone != workout.loadedSetsDone || workout.volumeKg != workout.loadedVolumeKg {
            workout.stampTotals()
            corrected += 1
        }
        return corrected
    }

    /// Full read-only detail for a finished workout, for `WorkoutDetailView`.
    /// Returns an empty placeholder if the workout can't be found.
    func workoutDetail(id: UUID) -> WorkoutDetail {
        guard let model = fetchWorkoutModel(id: id) else {
            // Imported Apple Health sessions live in the local Health store and carry no sets.
            if let imported = importedHealthWorkout(id: id) {
                return WorkoutDetail(
                    id: imported.id, title: imported.title, startedAt: imported.startedAt,
                    endedAt: imported.endedAt, isBackfilled: true
                )
            }
            return WorkoutDetail(title: "", startedAt: Date())
        }
        let entries = (model.exercises ?? []).sorted { $0.order < $1.order }.map { exerciseModel in
            let info = exerciseModel.exercise.map { exerciseInfo(for: $0) }
                ?? ExerciseInfo(name: "Deleted exercise", primary: [], equipment: "other")
            return WorkoutExerciseEntry(model: exerciseModel, exercise: info)
        }
        return WorkoutDetail(
            id: model.id, title: model.title, startedAt: model.startedAt, endedAt: model.endedAt,
            exercises: entries, notes: model.notes, isBackfilled: model.isBackfilled,
            prCount: prCount(for: model.id), routineGlyphs: routineGlyphs(for: entries),
            canEditNotes: model.endedAt != nil
        )
    }

    /// Every finished workout's start date, for `Streaks.weekly` — imported Apple Health
    /// sessions included, since a session logged on the Watch still broke the rest day.
    ///
    /// Fetches the one column it reads (`propertiesToFetch`), so Home, Coach, Consistency, the
    /// widgets and the notification scheduler no longer materialise every workout row for a
    /// list of dates. Pass `finishedWorkouts` to read the dates off a list already in hand.
    func workoutDates(finishedWorkouts: [WorkoutModel]? = nil) -> [Date] {
        let own: [Date]
        if let finishedWorkouts {
            own = finishedWorkouts.map(\.startedAt)
        } else {
            var descriptor = FetchDescriptor<WorkoutModel>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.propertiesToFetch = [\.startedAt]
            own = fetch(descriptor).map(\.startedAt)
        }
        return own + importedHealthWorkouts().map(\.startedAt)
    }

    /// Recovery stimulus events (`GymCore.Recovery`) from completed, non-warm-up sets of
    /// finished workouts started on or after `since`. Primary movers get a full share, secondary
    /// movers half; effort comes from the set's RPE, mapped to an RIR-based factor.
    func recoveryEvents(since: Date) -> [StimulusEvent] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil && $0.startedAt >= since }
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: predicate)
        let workouts = fetch(descriptor)
        return workouts.flatMap(recoveryEvents(in:))
    }
}
