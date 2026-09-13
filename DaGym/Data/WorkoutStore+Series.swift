import Foundation
import GymCore
import SwiftData

/// Per-exercise and body-wide chart data for `ExerciseChartView` and `ProgressChartsSection`/
/// `ProgressView` (plan.md §6.4). Pure math lives in `GymCore.ExerciseSeries`/`BodySeries`; this
/// extension only converts SwiftData models into their plain inputs.
extension WorkoutStore {
    /// One exercise's chart series, oldest session first, windowed to the trailing `months`
    /// (nil = all history).
    struct ExerciseSeriesBundle {
        var e1rm: [(date: Date, value: Double)]
        var topSet: [(date: Date, value: Double)]
        var volume: [(date: Date, value: Double)]
        var mostCommonWeight: Double?
        /// Every distinct weight logged in the window, heaviest first — options for the reps
        /// metric's weight picker.
        var distinctWeights: [Double]
        /// Last minus first e1RM point in the window; zero with fewer than two points.
        var e1rmTrendDeltaKg: Double
        /// Rating on each session's top set, by session date — tints the top-set line's dots.
        var topSetRPE: [Date: Double] = [:]
        /// No counting set in the window carried a load: the weight charts would be flat zeros,
        /// so the chart plots `bestReps`/`totalReps` instead.
        var neverLoaded = false
        var bestReps: [(date: Date, value: Int)] = []
        var totalReps: [(date: Date, value: Int)] = []
    }

    /// Body-wide effort data for `EffortCard` (features.md adopt 9).
    struct EffortSeriesBundle {
        var weeks: [EffortWeek]
        var histogram: [(effort: Effort, count: Int)]
        var ratedSets: Int
    }

    /// One calendar week's headline numbers, for the "THIS WEEK" strip and its week-over-week
    /// deltas.
    struct WeekStats {
        var volumeKg: Double
        var sets: Int
        var workouts: Int
        var avgDurationSeconds: Int
    }

    /// Body-wide chart data for `ProgressChartsSection`/`ProgressView`.
    struct BodySeriesBundle {
        var weeklyVolume: [(weekStart: Date, volumeKg: Double)]
        /// Sets per muscle over the requested `balanceWindow` (default: trailing 7 days).
        var setsPerMuscle: [Muscle: Double]
        var sessionDurations: [(date: Date, durationSeconds: Int)]
        var thisWeek: WeekStats
        var lastWeek: WeekStats
    }

    func exerciseSeries(exerciseID: UUID, months: Int?) -> ExerciseSeriesBundle {
        let sessions = exerciseSessions(exerciseID: exerciseID, months: months)
        let e1rm = ExerciseSeries.e1rm(sessions: sessions)
        let delta: Double
        if e1rm.count > 1, let first = e1rm.first?.value, let last = e1rm.last?.value {
            delta = last - first
        } else {
            delta = 0
        }
        let weights = Set(sessions.flatMap(\.sets).filter { $0.kind.countsTowardStats }.map(\.weightKg))
        return ExerciseSeriesBundle(
            e1rm: e1rm,
            topSet: ExerciseSeries.topSet(sessions: sessions),
            volume: ExerciseSeries.volume(sessions: sessions),
            mostCommonWeight: ExerciseSeries.mostCommonWeight(sessions: sessions),
            distinctWeights: weights.sorted(by: >),
            e1rmTrendDeltaKg: delta,
            topSetRPE: ExerciseSeries.topSetRPE(sessions: sessions),
            neverLoaded: ExerciseSeries.isNeverLoaded(sessions: sessions),
            bestReps: ExerciseSeries.bestReps(sessions: sessions),
            totalReps: ExerciseSeries.totalReps(sessions: sessions)
        )
    }

    /// `weeks` of mean effort per week plus the all-window histogram; `ratedSets` is 0 when the
    /// lifter has never rated a set, which is the card's cue to stay hidden.
    func effortSeries(weeks: Int, calendar: Calendar = .current, now: Date = Date()) -> EffortSeriesBundle {
        let since = calendar.date(byAdding: .weekOfYear, value: -weeks, to: now)
        let workouts = bodyWorkouts(since: since, calendar: calendar)
        return EffortSeriesBundle(
            weeks: EffortSeries.weeklyEffort(workouts: workouts, calendar: calendar),
            histogram: EffortSeries.histogram(workouts: workouts),
            ratedSets: EffortSeries.ratedSetCount(workouts: workouts)
        )
    }

    /// Reps performed at `weight` per session — the data behind the REPS metric.
    func repsAtWeightSeries(
        exerciseID: UUID, months: Int?, weight: Double
    ) -> [(date: Date, value: Int)] {
        ExerciseSeries.repsAtWeight(
            sessions: exerciseSessions(exerciseID: exerciseID, months: months), weight: weight
        )
    }

    /// `weeks` of weekly volume history, sets-per-muscle over `balanceWindow` (trailing 7 days
    /// by default; `.thisWeek(calendar)`, `.days(30)` or `.allTime` for the balance map's other
    /// horizons — with `hardOnly` counting only RIR ≤ 1 / failure / AMRAP sets), every session's
    /// duration, and this/last week's stats.
    func bodySeries(
        weeks: Int, calendar: Calendar = .current, balanceWindow: BalanceWindow = .days(7),
        hardOnly: Bool = false, now: Date = Date()
    ) -> BodySeriesBundle {
        let weeksSince = calendar.date(byAdding: .weekOfYear, value: -weeks, to: now) ?? now
        let balanceSince = balanceWindow.earliestDate(now: now, calendar: calendar)
        let since = balanceSince.map { min($0, weeksSince) }
        let workouts = bodyWorkouts(since: since, calendar: calendar)
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)
        let lastStart = lastWeekStart ?? thisWeekStart
        let perMuscle = BodySeries.setsPerMuscle(
            workouts: workouts, window: balanceWindow, now: now, calendar: calendar, hardOnly: hardOnly
        )
        return BodySeriesBundle(
            weeklyVolume: BodySeries.weeklyVolume(workouts: workouts, calendar: calendar),
            setsPerMuscle: perMuscle,
            sessionDurations: BodySeries.sessionDurations(workouts: workouts),
            thisWeek: weekStats(workouts: workouts, weekStart: thisWeekStart, calendar: calendar),
            lastWeek: weekStats(workouts: workouts, weekStart: lastStart, calendar: calendar)
        )
    }

    // MARK: - Helpers

    private func exerciseSessions(exerciseID: UUID, months: Int?) -> [ExerciseSession] {
        let calendar = Calendar.current
        let since = months.flatMap { calendar.date(byAdding: .month, value: -$0, to: Date()) }
        let models = finishedWorkoutsOldestFirst()
        return models.compactMap { workout -> ExerciseSession? in
            if let since, workout.startedAt < since { return nil }
            guard let match = (workout.exercises ?? []).first(where: { $0.exercise?.id == exerciseID }) else {
                return nil
            }
            let sets = performedSets(from: match.sets, sessionDate: workout.startedAt)
            guard !sets.isEmpty else { return nil }
            return ExerciseSession(date: workout.startedAt, sets: sets)
        }
    }

    /// Finished workouts from `since` on (all of them when nil), oldest first.
    private func bodyWorkouts(since: Date?, calendar: Calendar) -> [BodyWorkout] {
        let predicate: Predicate<WorkoutModel>
        if let since {
            predicate = #Predicate<WorkoutModel> { $0.endedAt != nil && $0.startedAt >= since }
        } else {
            predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(bodyWorkout(from:))
    }

    private func bodyWorkout(from workout: WorkoutModel) -> BodyWorkout {
        let duration = workout.endedAt.map { max(0, Int($0.timeIntervalSince(workout.startedAt))) } ?? 0
        let entries = (workout.exercises ?? []).compactMap { exerciseModel -> BodyWorkout.MuscleEntry? in
            guard let exercise = exerciseModel.exercise else { return nil }
            let sets = performedSets(from: exerciseModel.sets, sessionDate: workout.startedAt)
            guard !sets.isEmpty else { return nil }
            return BodyWorkout.MuscleEntry(
                primary: exercise.primary, secondary: exercise.secondary, sets: sets
            )
        }
        return BodyWorkout(date: workout.startedAt, durationSeconds: duration, entries: entries)
    }

    private func performedSets(from setLogs: [SetLogModel]?, sessionDate: Date) -> [PerformedSet] {
        (setLogs ?? []).filter(\.isCompleted).map { setLog in
            PerformedSet(
                kind: setLog.setKind, weightKg: setLog.weightKg, reps: setLog.reps,
                durationSeconds: setLog.durationSeconds, date: sessionDate, rpe: setLog.rpe
            )
        }
    }

    private func weekStats(workouts: [BodyWorkout], weekStart: Date, calendar: Calendar) -> WeekStats {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else {
            return WeekStats(volumeKg: 0, sets: 0, workouts: 0, avgDurationSeconds: 0)
        }
        let inWeek = workouts.filter { interval.contains($0.date) }
        let countingSets = inWeek.flatMap(\.entries).flatMap(\.sets).filter { $0.kind.countsTowardStats }
        let volume = countingSets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        let avgDuration = inWeek.isEmpty ? 0 : inWeek.reduce(0) { $0 + $1.durationSeconds } / inWeek.count
        return WeekStats(
            volumeKg: volume, sets: countingSets.count, workouts: inWeek.count,
            avgDurationSeconds: avgDuration
        )
    }

    private func finishedWorkoutsOldestFirst() -> [WorkoutModel] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
