import Foundation
import GymCore
import SwiftData

/// One earned record, formatted for display — see `GymCore.PersonalRecords.formatLine`.
struct PersonalRecordLine: Identifiable, Hashable {
    var id = UUID()
    var kindLabel: String
    var line: String
    var date: Date
}

/// Every cached record for one exercise, for `PersonalRecordsView`.
struct ExerciseRecords: Identifiable {
    var id: UUID
    var exerciseName: String
    var records: [PersonalRecordLine]
}

extension WorkoutStore {
    /// All cached `PersonalRecordModel`s, grouped by exercise and sorted alphabetically.
    /// Records within an exercise are ordered by kind, then newest first. `unit` controls how
    /// each line is formatted; defaults to kg for callers that haven't gone unit-aware yet.
    func personalRecords(unit: WeightUnit = .kg) -> [ExerciseRecords] {
        let models = fetch(FetchDescriptor<PersonalRecordModel>())
        let grouped = Dictionary(grouping: models) { $0.exerciseID }
        return grouped
            .compactMap { exerciseID, models -> ExerciseRecords? in
                guard let exerciseID, let exerciseModel = fetchExerciseModel(id: exerciseID) else {
                    return nil
                }
                let order = PRKind.allCases
                let lines = models
                    .sorted { lhs, rhs in
                        let li = order.firstIndex(of: PRKind(rawValue: lhs.kind) ?? .e1rm) ?? 0
                        let ri = order.firstIndex(of: PRKind(rawValue: rhs.kind) ?? .e1rm) ?? 0
                        return li != ri ? li < ri : lhs.date > rhs.date
                    }
                    .map { self.personalRecordLine($0, unit: unit) }
                return ExerciseRecords(id: exerciseID, exerciseName: exerciseModel.name, records: lines)
            }
            .sorted { $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending }
    }

    private func personalRecordLine(_ model: PersonalRecordModel, unit: WeightUnit) -> PersonalRecordLine {
        let kind = PRKind(rawValue: model.kind) ?? .e1rm
        let record = PersonalRecord(
            kind: kind, value: model.value, weightKg: model.weightKg, reps: model.reps, date: model.date
        )
        return PersonalRecordLine(
            kindLabel: kind.displayName,
            line: PersonalRecords.formatLine(record, unit: unit, distanceUnit: preferredDistanceUnit),
            date: model.date
        )
    }
}

// MARK: - Evaluation, event log and rebuild (GymCore.PersonalRecords)

extension WorkoutStore {
    /// Headline records only (e1RM) — the count the user sees; other kinds are logged silently.
    /// Counts `PersonalRecordEventModel` rows, which are append-only, so a workout's PR count
    /// doesn't decay when a later session beats it.
    func prCount(for workoutID: UUID) -> Int {
        let headline = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordEventModel> {
            $0.workoutID == workoutID && $0.kind == headline
        }
        return fetchCount(FetchDescriptor(predicate: predicate))
    }

    /// `prCount(for:)` for every workout at once — one fetch of the headline events, grouped by
    /// workout, for `history()`, which used to issue one `fetchCount` per finished workout.
    func prCountsByWorkout() -> [UUID: Int] {
        let headline = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordEventModel> { $0.kind == headline }
        var counts: [UUID: Int] = [:]
        for event in fetch(FetchDescriptor(predicate: predicate)) {
            guard let workoutID = event.workoutID else { continue }
            counts[workoutID, default: 0] += 1
        }
        return counts
    }

    /// Headline (e1RM) records set by workouts started in `[from, to)`, from the event log.
    func prCount(from: Date, to: Date) -> Int {
        let headline = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordEventModel> {
            $0.kind == headline && $0.date >= from && $0.date < to
        }
        return fetchCount(FetchDescriptor(predicate: predicate))
    }

    // MARK: - Personal records (GymCore.PersonalRecords)

    /// Evaluates every `PRKind` per exercise and caches all of them (`PersonalRecordModel`), but
    /// the summary/banner still surfaces only the e1RM kind per exercise — matching the existing
    /// "one PR line per exercise" UI. The other kinds (maxWeight, volume, maxRepsAtWeight, …) are
    /// cached for `exerciseInfo(for:)`-style lookups and future screens without changing what the
    /// Finish summary shows.
    ///
    /// `finishedWorkouts` is the finished list *without* this workout (newest first), as `finish`
    /// read it before stamping `endedAt`; left nil it is fetched here.
    func evaluatePRs(
        session: WorkoutSession, workout: WorkoutModel, unit: WeightUnit = .kg,
        finishedWorkouts: [WorkoutModel]? = nil
    ) -> [PersonalRecordInfo] {
        // A workout dated before one that is already logged cannot be judged incrementally: the
        // cache it would be compared against holds records set *after* it. That used to mean a
        // backfill earned nothing and the cache never learned of it either — so a Friday
        // backfill of Tuesday's 140 × 5 left the cache on Thursday's 148, and the following
        // week's 135 × 5 was crowned "PR! e1RM 153" with a bigger lift sitting in the history
        // and plotted on the very same chart. Worse, `rebuildPersonalRecords` replays in date
        // order and would have awarded the 140 and refused the 135, so deleting an unrelated
        // workout silently changed who held the records.
        //
        // There is only one honest answer for a past-dated session and it is the replay, which
        // is exactly what deleting a workout already does. No banner: a session logged for last
        // Tuesday is not a PR moment today, and the records list shows what it earned.
        let latest = (finishedWorkouts ?? finishedWorkoutModelsNewestFirst())
            .first { $0.id != workout.id }?.startedAt
        if let latest, workout.startedAt < latest {
            rebuildPersonalRecords()
            return []
        }
        return session.exercises.compactMap { entry -> PersonalRecordInfo? in
            let performed = performedSets(in: entry, date: workout.startedAt)
            guard !performed.isEmpty else { return nil }
            let records = PersonalRecords.evaluate(
                newSets: performed, existing: existingRecords(exerciseID: entry.exercise.id),
                workoutDate: workout.startedAt
            )
            for record in records {
                cacheRecord(record, exerciseID: entry.exercise.id, workoutID: workout.id)
                logRecordEvent(record, exerciseID: entry.exercise.id, workoutID: workout.id)
            }
            guard let e1rm = records.first(where: { $0.kind == .e1rm }) else { return nil }
            return PersonalRecordInfo(
                exerciseName: entry.exercise.name, line: PersonalRecords.formatLine(e1rm, unit: unit)
            )
        }
    }

    /// Throws away the PR cache and event log and replays every finished workout, oldest first,
    /// so both reflect exactly the sets that still exist. Used after deleting a workout, after a
    /// backup import and for a past-dated finish; cheap enough for a settings "recompute" too.
    ///
    /// The replay keeps the cache in memory (`[exercise: [kind/weight: record]]`) and writes the
    /// rows once at the end. Upserting through the store as it went cost a fetch of the
    /// exercise's records plus a `fetchFirst` per kind per exercise per workout — O(workouts ×
    /// exercises × kinds) queries on the main thread, seconds of freeze on a long history for
    /// every delete.
    func rebuildPersonalRecords() {
        let state = storeSignposter.beginInterval("rebuildPersonalRecords")
        defer { storeSignposter.endInterval("rebuildPersonalRecords", state) }
        deleteAll(PersonalRecordModel.self)
        deleteAll(PersonalRecordEventModel.self)
        var cache: [UUID: [PRCacheKey: CachedRecord]] = [:]
        let bodyweight = bodyweightLookup()
        for workout in finishedWorkoutModelsNewestFirst().reversed() {
            replayRecords(in: workout, cache: &cache, bodyweight: bodyweight)
        }
        for (exerciseID, records) in cache {
            for cached in records.values {
                let model = PersonalRecordModel(exerciseID: exerciseID, kind: cached.record.kind.rawValue)
                context.insert(model)
                Self.apply(cached.record, workoutID: cached.workoutID, to: model)
            }
        }
        save()
    }

    /// `maxRepsAtWeight` keeps one row per weight (a lifter can hold separate rep records at 60 kg
    /// and 80 kg); every other kind keeps a single best row — the same rule `cacheRecord` upserts by.
    private struct PRCacheKey: Hashable {
        var kind: PRKind
        var weightKg: Double?

        init(_ record: PersonalRecord) {
            kind = record.kind
            weightKg = record.kind == .maxRepsAtWeight ? record.weightKg : nil
        }
    }

    private struct CachedRecord {
        var record: PersonalRecord
        var workoutID: UUID
    }

    /// Every weigh-in, newest first, read once — so the replay's per-exercise "bodyweight as of
    /// this workout" (`latestBodyMeasurement(asOf:)`) is a scan of that array, not a query per
    /// assisted or weighted-bodyweight row in history.
    private func bodyweightLookup() -> (Date) -> Double? {
        let descriptor = FetchDescriptor<BodyMeasurementModel>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let readings = fetch(descriptor).map { (date: $0.date, kg: $0.bodyweightKg) }
        return { asOf in readings.first { $0.date <= asOf }.flatMap(\.kg) }
    }

    private func replayRecords(
        in workout: WorkoutModel, cache: inout [UUID: [PRCacheKey: CachedRecord]],
        bodyweight: @escaping (Date) -> Double?
    ) {
        for exerciseModel in (workout.exercises ?? []).sorted(by: { $0.order < $1.order }) {
            guard let exercise = exerciseModel.exercise else { continue }
            let entry = WorkoutExerciseEntry(model: exerciseModel, exercise: ExerciseInfo(model: exercise))
            let performed = performedSets(in: entry, date: workout.startedAt, bodyweight: bodyweight)
            guard !performed.isEmpty else { continue }
            // Replayed in date order, so every earlier workout is already in the cache and no
            // later one is: a backfill can never claim a record against a session after it.
            let existing = (cache[exercise.id] ?? [:]).values.map(\.record)
            let records = PersonalRecords.evaluate(
                newSets: performed, existing: existing, workoutDate: workout.startedAt
            )
            for record in records {
                cache[exercise.id, default: [:]][PRCacheKey(record)] = CachedRecord(
                    record: record, workoutID: workout.id
                )
                logRecordEvent(record, exerciseID: exercise.id, workoutID: workout.id)
            }
        }
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) {
        let models = fetch(FetchDescriptor<Model>())
        models.forEach(context.delete)
    }

    private func logRecordEvent(_ record: PersonalRecord, exerciseID: UUID, workoutID: UUID) {
        context.insert(
            PersonalRecordEventModel(
                exerciseID: exerciseID, workoutID: workoutID, kind: record.kind.rawValue,
                value: record.value, weightKg: record.weightKg, reps: record.reps, date: record.date
            )
        )
    }

    /// `bodyweight` resolves the lifter's bodyweight as of a date; the default is one store
    /// query, the replay passes an in-memory lookup over every weigh-in read once.
    private func performedSets(
        in entry: WorkoutExerciseEntry, date: Date, bodyweight: ((Date) -> Double?)? = nil
    ) -> [PerformedSet] {
        let style = entry.exercise.loggingStyle
        let bodyweightKg = Self.needsBodyweight(style)
            ? (bodyweight?(date) ?? latestBodyMeasurement(asOf: date)?.bodyweightKg) : nil
        return entry.sets.filter { $0.isDone && $0.kind.countsTowardStats }.map { setEntry in
            PerformedSet(
                kind: setEntry.kind, weightKg: Self.loadedWeightKg(setEntry, style: style),
                reps: setEntry.reps, durationSeconds: setEntry.durationSeconds,
                assistanceKg: Self.assistanceKg(setEntry, style: style),
                bodyweightKg: bodyweightKg, date: date,
                distanceMeters: style == .cardio ? setEntry.distanceMeters : nil
            )
        }
    }

    /// Bodyweight is part of the load for exactly two styles. A bodyweight-only exercise must
    /// **not** carry one: folding the lifter's mass in gave 12 air squats an e1RM of ~113 kg and
    /// a Bronze "Bodyweight Squat" badge, and only for lifters who had logged a weigh-in — two
    /// identical lifters saw different PR lists.
    static func needsBodyweight(_ style: ExerciseInfo.LoggingStyle) -> Bool {
        style == .assisted || style == .weightedBodyweight
    }

    /// External load actually lifted (`PerformedSet.weightKg`). **The** conversion from a logged
    /// row to the number every total may use — `WorkoutStore+Series` and `+Consistency` read it
    /// too.
    ///
    /// An assisted row stores the assistance dialled in as its `weightKg` (that is what the set
    /// row edits, and what `ProgressionEngine+AssistedTimed` reads back). Taken literally it
    /// made 30 kg of help into 30 kg lifted: "Heaviest 30 kg", "Best set 30 × 8 (240 kg)",
    /// 240 kg of lifetime tonnage, and a top-set chart that *fell* as the lifter got stronger.
    /// Assistance is not load, so it is 0 here and travels in `assistanceKg` instead.
    nonisolated static func loadedWeightKg(
        _ setEntry: SetEntry, style: ExerciseInfo.LoggingStyle
    ) -> Double {
        style.loadedWeightKg(logged: setEntry.weightKg)
    }

    /// The assistance for an assisted row: what was **logged**, not what was prescribed.
    ///
    /// The set row for an assisted lift edits `weightKg`, so that is the number the lifter
    /// actually dialled in; `assistanceKg` only carries what the prescription (or a voice log)
    /// put there, and is never updated afterwards. Reading the prescription first meant a lifter
    /// who went from 30 kg of help down to 20 had their e1RM computed off the stale 30 and
    /// missed the PR — and an assisted exercise added mid-workout had no prescription at all, so
    /// `assistanceKg` was nil, the set read as weighted-bodyweight, and bodyweight + 20 gave a
    /// ~117 kg e1RM to someone who cannot do one unassisted pull-up.
    ///
    /// Resolution order matches `ProgressionEngine+AssistedTimed`, the other reader of these
    /// rows: the logged weight when there is one, the prescribed assistance otherwise. Never
    /// nil for an assisted set — its absence is what makes a set *not* assisted.
    nonisolated static func assistanceKg(
        _ setEntry: SetEntry, style: ExerciseInfo.LoggingStyle
    ) -> Double? {
        guard style == .assisted else { return nil }
        return setEntry.weightKg > 0 ? setEntry.weightKg : (setEntry.assistanceKg ?? 0)
    }

    /// Every cached record for this exercise, across all kinds — the `existing` bests that
    /// `PersonalRecords.evaluate` checks each new set against.
    private func existingRecords(exerciseID: UUID) -> [PersonalRecord] {
        let predicate = #Predicate<PersonalRecordModel> { $0.exerciseID == exerciseID }
        let models = fetch(FetchDescriptor(predicate: predicate))
        return models.compactMap { model in
            guard let kind = PRKind(rawValue: model.kind) else { return nil }
            return PersonalRecord(
                kind: kind, value: model.value, weightKg: model.weightKg, reps: model.reps, date: model.date
            )
        }
    }

    /// Upserts one PR into the cache. `maxRepsAtWeight` keeps one row per weight (a lifter can
    /// hold separate rep records at 60 kg and 80 kg); every other kind keeps a single best row.
    private func cacheRecord(_ record: PersonalRecord, exerciseID: UUID, workoutID: UUID) {
        let kind = record.kind.rawValue
        let weight = record.weightKg
        let byWeightToo = record.kind == .maxRepsAtWeight
        let predicate = #Predicate<PersonalRecordModel> {
            $0.exerciseID == exerciseID && $0.kind == kind && (!byWeightToo || $0.weightKg == weight)
        }
        let existing = fetchFirst(FetchDescriptor(predicate: predicate))
        let model = existing ?? PersonalRecordModel(exerciseID: exerciseID, kind: kind)
        if existing == nil { context.insert(model) }
        Self.apply(record, workoutID: workoutID, to: model)
    }

    private static func apply(_ record: PersonalRecord, workoutID: UUID, to model: PersonalRecordModel) {
        model.value = record.value
        model.weightKg = record.weightKg
        model.reps = record.reps
        model.date = record.date
        model.workoutID = workoutID
    }
}

extension ExerciseInfo.LoggingStyle {
    /// **The** rule, in one expression: the external load a logged row's weight represents.
    /// An assisted row's weight is the machine's help, and help is not load, so it is 0 — which
    /// also settles what an assisted set is worth in *volume*: `0 × reps = 0`.
    ///
    /// Zero reads harshly ("that set didn't count"), and bodyweight-minus-assistance would read
    /// better. It was rejected: it needs a bodyweight on file, so two identical lifters would
    /// see different tonnage (and a lifter with no weigh-in would see none); it only makes sense
    /// if bodyweight-only sets start counting their bodyweight too, which is a far bigger change;
    /// and it would contradict `PerformedSet.weightKg`, which the PR cache, the top-set chart and
    /// the e1RM already define as external load and nothing else. One convention everywhere beats
    /// a kinder number in some places. Assisted work still shows up as sets, reps, a falling
    /// least-assistance PR and a rising e1RM — volume is simply not where it is measured.
    ///
    /// Both row shapes funnel through here: `WorkoutStore.loadedWeightKg(_:style:)` for a live
    /// `SetEntry`, `WorkoutModel.loadedVolumeKg` for persisted `SetLogModel`s.
    func loadedWeightKg(logged weightKg: Double) -> Double {
        self == .assisted ? 0 : weightKg
    }
}
