import Foundation
import GymCore
import SwiftData

/// The trend reads: exercise history and forecast, weekly and per-muscle volume, adherence.
/// Windows are trailing calendar weeks from `now`, most recent first, the way the tool
/// descriptions say.
extension StoreCoachChatToolExecutor {
    // MARK: - get_exercise_history

    struct ExerciseHistoryPayload: Codable {
        var exerciseID: UUID
        var name: String
        var sessions: [HistorySessionPayload]
        var truncated: Bool
        var last12Weeks: HistorySummaryPayload

        enum CodingKeys: String, CodingKey {
            case name, sessions, truncated
            case exerciseID = "exercise_id"
            case last12Weeks = "last_12_weeks"
        }
    }

    struct HistorySessionPayload: Codable {
        var date: Date
        var sets: [LoggedSetPayload]
        var bestE1rmKg: Double?

        enum CodingKeys: String, CodingKey {
            case date, sets
            case bestE1rmKg = "best_e1rm_kg"
        }
    }

    struct HistorySummaryPayload: Codable {
        var sessions: Int
        var firstE1rmKg: Double?
        var lastE1rmKg: Double?
        var bestE1rmKg: Double?
        var changeKg: Double?
        var topWeightKg: Double?

        enum CodingKeys: String, CodingKey {
            case sessions
            case firstE1rmKg = "first_e1rm_kg"
            case lastE1rmKg = "last_e1rm_kg"
            case bestE1rmKg = "best_e1rm_kg"
            case changeKg = "change_kg"
            case topWeightKg = "top_weight_kg"
        }
    }

    /// Newest session first, capped at `maxSeriesSessions`; the 12-week summary is over every
    /// session in the window, capped or not.
    func exerciseHistory(_ arguments: ExerciseArguments) throws -> ExerciseHistoryPayload {
        let exercise = try resolveExercise(id: arguments.exerciseID, name: arguments.exerciseName)
        let cap = Self.maxSeriesSessions
        let history = store.exerciseHistory(exerciseID: exercise.id, limit: cap + 1)
        let sessions = history.prefix(cap).map { entry in
            HistorySessionPayload(
                date: entry.date,
                sets: entry.workingSets.map { set in
                    LoggedSetPayload(
                        kind: set.kind.rawValue, weightKg: Self.kg(set.weightKg), reps: set.reps,
                        rpe: set.effort?.rpe, durationSeconds: set.durationSeconds
                    )
                },
                bestE1rmKg: Self.kg(Self.bestE1RM(entry))
            )
        }
        return ExerciseHistoryPayload(
            exerciseID: exercise.id, name: exercise.name, sessions: sessions,
            truncated: history.count > cap, last12Weeks: summary(exerciseID: exercise.id)
        )
    }

    private func summary(exerciseID: UUID) -> HistorySummaryPayload {
        let since = calendar.date(byAdding: .weekOfYear, value: -ProgressForecast.windowWeeks, to: now())
        let entries = store.exerciseHistory(exerciseID: exerciseID, limit: Int.max)
            .filter { $0.date >= (since ?? .distantPast) && $0.date <= now() }
        let e1rms = entries.reversed().compactMap(Self.bestE1RM)
        let change: Double? = e1rms.count >= 2 ? (e1rms.last ?? 0) - (e1rms.first ?? 0) : nil
        return HistorySummaryPayload(
            sessions: entries.count, firstE1rmKg: Self.kg(e1rms.first), lastE1rmKg: Self.kg(e1rms.last),
            bestE1rmKg: Self.kg(e1rms.max()), changeKg: Self.kg(change),
            topWeightKg: Self.kg(entries.flatMap(\.workingSets).map(\.weightKg).max())
        )
    }

    static func bestE1RM(_ entry: ExerciseHistoryEntry) -> Double? {
        entry.workingSets.compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }.max()
    }

    // MARK: - forecast_e1rm

    struct ForecastPayload: Codable {
        var exerciseID: UUID
        var name: String
        var targetKg: Double
        var currentE1rmKg: Double?
        var slopeKgPerWeek: Double?
        var r2: Double?
        var sessions: Int
        var weeksToTarget: Double?
        var reachDate: Date?
        var caveat: String
        var caveatText: String

        enum CodingKeys: String, CodingKey {
            case name, r2, sessions, caveat
            case exerciseID = "exercise_id"
            case targetKg = "target_kg"
            case currentE1rmKg = "current_e1rm_kg"
            case slopeKgPerWeek = "slope_kg_per_week"
            case weeksToTarget = "weeks_to_target"
            case reachDate = "reach_date"
            case caveatText = "caveat_text"
        }
    }

    func forecast(_ arguments: ForecastArguments) throws -> ForecastPayload {
        let exercise = try resolveExercise(id: arguments.exerciseID, name: arguments.exerciseName)
        guard arguments.targetKg > 0, arguments.targetKg <= TrainingConstants.maxLoadKg else {
            throw CoachChatToolError.badArguments("target_kg must be 1–\(Int(TrainingConstants.maxLoadKg))")
        }
        let points = store.e1rmSeries(exerciseID: exercise.id).map { (date: $0.0, e1rmKg: $0.1) }
        guard let forecast = ProgressForecast.forecast(
            points: points, targetKg: arguments.targetKg, now: now(), calendar: calendar
        ) else {
            return ForecastPayload(
                exerciseID: exercise.id, name: exercise.name, targetKg: arguments.targetKg, sessions: 0,
                caveat: "no_sessions",
                caveatText: "No sessions of \(exercise.name) in the last "
                    + "\(ProgressForecast.windowWeeks) weeks."
            )
        }
        let slope = (forecast.slopeKgPerWeek * 100).rounded() / 100
        return ForecastPayload(
            exerciseID: exercise.id, name: exercise.name, targetKg: arguments.targetKg,
            currentE1rmKg: Self.kg(forecast.currentE1RM), slopeKgPerWeek: slope,
            r2: Self.fraction(forecast.r2), sessions: forecast.sessions,
            weeksToTarget: forecast.weeksToTarget.map { ($0 * 10).rounded() / 10 },
            reachDate: forecast.reachDate, caveat: forecast.caveat.rawValue,
            caveatText: Self.caveatText(forecast.caveat, sessions: forecast.sessions)
        )
    }

    static func caveatText(_ caveat: ProgressForecast.Caveat, sessions: Int) -> String {
        switch caveat {
        case .tooFewSessions:
            "Only \(sessions) sessions in the last \(ProgressForecast.windowWeeks) weeks — too few for "
                + "a trend."
        case .flatOrNegative: "The trend is flat or falling, so no date can be given."
        case .alreadyThere: "The latest estimated 1RM already meets the target."
        case .ok: "A straight-line forecast; real progress is rarely straight."
        }
    }

    // MARK: - get_weekly_volume

    struct WeeklyVolumePayload: Codable {
        var weeks: [WeekVolumePayload]
    }

    struct WeekVolumePayload: Codable {
        var weekStart: Date
        var sessions: Int
        var sets: Int
        var volumeKg: Double
        var minutes: Int

        enum CodingKeys: String, CodingKey {
            case sessions, sets, minutes
            case weekStart = "week_start"
            case volumeKg = "volume_kg"
        }
    }

    /// One entry per calendar week, the current (partial) week first, including empty weeks so
    /// a gap reads as zero rather than vanishing.
    func weeklyVolume(_ arguments: WeeksArguments) -> WeeklyVolumePayload {
        let weeks = arguments.clampedWeeks
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now())?.start else {
            return WeeklyVolumePayload(weeks: [])
        }
        let starts = (0..<weeks).compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        guard let earliest = starts.last else { return WeeklyVolumePayload(weeks: []) }
        var byWeek: [Date: WeekVolumePayload] = [:]
        for workout in store.finishedWorkoutModelsNewestFirst() where workout.startedAt >= earliest {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start else {
                continue
            }
            var week = byWeek[start] ?? WeekVolumePayload(
                weekStart: start, sessions: 0, sets: 0, volumeKg: 0, minutes: 0
            )
            week.sessions += 1
            week.sets += workout.hasStampedTotals ? workout.setsDone : workout.loadedSetsDone
            week.volumeKg += workout.hasStampedTotals ? workout.volumeKg : workout.loadedVolumeKg
            if let endedAt = workout.endedAt {
                week.minutes += max(0, Int(endedAt.timeIntervalSince(workout.startedAt) / 60))
            }
            byWeek[start] = week
        }
        return WeeklyVolumePayload(weeks: starts.map { start in
            var week = byWeek[start] ?? WeekVolumePayload(
                weekStart: start, sessions: 0, sets: 0, volumeKg: 0, minutes: 0
            )
            week.volumeKg = Self.kg(week.volumeKg)
            return week
        })
    }

    // MARK: - get_muscle_volume

    struct MuscleVolumePayload: Codable {
        var weeks: Int
        var floorSetsPerWeek: Double
        var muscles: [MuscleSetsPayload]

        enum CodingKeys: String, CodingKey {
            case weeks, muscles
            case floorSetsPerWeek = "floor_sets_per_week"
        }
    }

    struct MuscleSetsPayload: Codable {
        var muscle: String
        var setsPerWeek: Double
        var totalSets: Double
        var status: String

        enum CodingKeys: String, CodingKey {
            case muscle, status
            case setsPerWeek = "sets_per_week"
            case totalSets = "total_sets"
        }
    }

    /// The same per-muscle count Progress's balance map shows (primary 1, secondary 0.5), over
    /// the trailing `weeks × 7` days, against the coach's own coverage floor expressed per week.
    func muscleVolume(_ arguments: WeeksArguments) -> MuscleVolumePayload {
        let weeks = arguments.clampedWeeks
        let sets = store.bodySeries(
            weeks: weeks, calendar: calendar, balanceWindow: .days(weeks * 7), now: now()
        ).setsPerMuscle
        let floor = TrainingConstants.coachMinSetsPerMuscleInWindow
            / (Double(TrainingConstants.coachCoverageWindowDays) / 7)
        let muscles = Muscle.allCases.map { muscle -> MuscleSetsPayload in
            let total = sets[muscle, default: 0]
            let perWeek = total / Double(weeks)
            let status = total == 0 ? "untrained" : (perWeek < floor ? "below_floor" : "ok")
            return MuscleSetsPayload(
                muscle: muscle.displayName, setsPerWeek: (perWeek * 10).rounded() / 10,
                totalSets: (total * 10).rounded() / 10, status: status
            )
        }
        .sorted { $0.setsPerWeek > $1.setsPerWeek }
        return MuscleVolumePayload(weeks: weeks, floorSetsPerWeek: floor, muscles: muscles)
    }
}
