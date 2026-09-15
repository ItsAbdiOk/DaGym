import Foundation
import GymCore
import SwiftData

/// The remaining reads: personal records, recovery, bodyweight and the library search — the
/// tools whose answers are lists the model filters rather than trends it interprets.
extension StoreCoachChatToolExecutor {
    // MARK: - get_personal_records

    struct RecordsPayload: Codable {
        var exercises: [ExerciseRecordsPayload]
    }

    struct ExerciseRecordsPayload: Codable {
        var exerciseID: UUID
        var name: String
        var records: [RecordPayload]

        enum CodingKeys: String, CodingKey {
            case name, records
            case exerciseID = "exercise_id"
        }
    }

    struct RecordPayload: Codable {
        var kind: String
        var value: Double
        var weightKg: Double
        var reps: Int
        var date: Date

        enum CodingKeys: String, CodingKey {
            case kind, value, reps, date
            case weightKg = "weight_kg"
        }
    }

    /// The PR cache as raw numbers: `value` is kg for e1rm/max_weight/volume, reps for
    /// max_reps_at_weight, seconds for longest_hold, metres for longest_distance.
    func personalRecords(_ arguments: ExerciseArguments) throws -> RecordsPayload {
        var only: UUID?
        if arguments.exerciseID != nil || arguments.exerciseName != nil {
            only = try resolveExercise(id: arguments.exerciseID, name: arguments.exerciseName).id
        }
        let models = store.fetch(FetchDescriptor<PersonalRecordModel>())
            .filter { only == nil || $0.exerciseID == only }
        let grouped = Dictionary(grouping: models) { $0.exerciseID }
        let exercises = store.fetchExerciseModels(ids: Set(grouped.keys.compactMap { $0 }))
        let payloads = grouped.compactMap { exerciseID, records -> ExerciseRecordsPayload? in
            guard let exerciseID, let exercise = exercises[exerciseID] else { return nil }
            let lines = records
                .sorted { $0.kind == $1.kind ? $0.date > $1.date : $0.kind < $1.kind }
                .map { record in
                    RecordPayload(
                        kind: Self.snakeCase(record.kind), value: Self.kg(record.value),
                        weightKg: Self.kg(record.weightKg), reps: record.reps, date: record.date
                    )
                }
            return ExerciseRecordsPayload(exerciseID: exerciseID, name: exercise.name, records: lines)
        }
        .sorted { $0.name < $1.name }
        return RecordsPayload(exercises: payloads)
    }

    /// "maxRepsAtWeight" → "max_reps_at_weight", so record kinds read like every other key.
    static func snakeCase(_ camel: String) -> String {
        camel.reduce(into: "") { result, character in
            if character.isUppercase { result.append("_") }
            result.append(contentsOf: character.lowercased())
        }
    }

    // MARK: - get_adherence

    struct AdherencePayload: Codable {
        var weeks: Int
        var planned: Int
        var kept: Int
        var percent: Int?
        var perWeek: [WeekAdherencePayload]
        var weeklyGoal: Int
        var currentStreakWeeks: Int
        var longestStreakWeeks: Int
        var sessionsThisWeek: Int

        enum CodingKeys: String, CodingKey {
            case weeks, planned, kept, percent
            case perWeek = "per_week"
            case weeklyGoal = "weekly_goal"
            case currentStreakWeeks = "current_streak_weeks"
            case longestStreakWeeks = "longest_streak_weeks"
            case sessionsThisWeek = "sessions_this_week"
        }
    }

    struct WeekAdherencePayload: Codable {
        var weekStart: Date
        var planned: Int
        var kept: Int

        enum CodingKeys: String, CodingKey {
            case planned, kept
            case weekStart = "week_start"
        }
    }

    /// Planned versus kept per trailing 7-day block (the same judgement `AdherenceSummary`
    /// makes), plus the goal streak `Streaks.weekly` computes for Home.
    func adherence(_ arguments: WeeksArguments) -> AdherencePayload {
        let weeks = arguments.clampedWeeks
        let plan = store.schedule()
        let logged = store.finishedWorkoutModelsNewestFirst().map(\.startedAt)
        let total = AdherenceSummary.over(
            weeks: weeks, schedule: plan, loggedWorkoutDates: logged, now: now(), calendar: calendar
        )
        let trained = Set(logged.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now())
        let perWeek = (0..<weeks).compactMap { week -> WeekAdherencePayload? in
            guard let end = calendar.date(byAdding: .day, value: -(week * 7), to: today),
                  let start = calendar.date(byAdding: .day, value: -6, to: end) else { return nil }
            var block = WeekAdherencePayload(weekStart: start, planned: 0, kept: 0)
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                      !plan.routineIDs(on: day, calendar: calendar).isEmpty else { continue }
                block.planned += 1
                if trained.contains(day) { block.kept += 1 }
            }
            return block
        }
        let streak = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: weeklyGoal, calendar: calendar, now: now()
        )
        return AdherencePayload(
            weeks: weeks, planned: total.planned, kept: total.kept, percent: total.percent, perWeek: perWeek,
            weeklyGoal: weeklyGoal, currentStreakWeeks: streak.current, longestStreakWeeks: streak.longest,
            sessionsThisWeek: streak.thisWeekCount
        )
    }

    // MARK: - get_recovery

    struct RecoveryPayload: Codable {
        var muscles: [MuscleRecoveryPayload]
        var ready: [String]
        var untrainedThisWeek: [String]

        enum CodingKeys: String, CodingKey {
            case muscles, ready
            case untrainedThisWeek = "untrained_this_week"
        }
    }

    struct MuscleRecoveryPayload: Codable {
        var muscle: String
        var spent: Double
        var recoveredBy: Date?

        enum CodingKeys: String, CodingKey {
            case muscle, spent
            case recoveredBy = "recovered_by"
        }
    }

    /// "Ready" is the recovery map's own fresh band: under a third spent, or not trained at all
    /// in the window.
    func recovery() -> RecoveryPayload {
        let snapshot = store.recoverySnapshot(now: now(), calendar: calendar)
        let muscles = snapshot.perMuscle.map { reading in
            MuscleRecoveryPayload(
                muscle: reading.muscle.displayName, spent: Self.fraction(reading.spent),
                recoveredBy: reading.recoveredBy
            )
        }
        let trained = Set(snapshot.perMuscle.map(\.muscle))
        let ready = Muscle.allCases.filter { muscle in
            !trained.contains(muscle) || (snapshot.map[muscle] ?? 0) < Self.readySpentThreshold
        }
        return RecoveryPayload(
            muscles: muscles, ready: ready.map(\.displayName),
            untrainedThisWeek: snapshot.untrainedMuscles.map(\.displayName)
        )
    }

    static let readySpentThreshold = 0.34

    // MARK: - get_body_measurements

    struct BodyPayload: Codable {
        var weeks: Int
        var latestKg: Double?
        var changeKg: Double?
        var readings: [BodyReadingPayload]
        var truncated: Bool

        enum CodingKeys: String, CodingKey {
            case weeks, readings, truncated
            case latestKg = "latest_kg"
            case changeKg = "change_kg"
        }
    }

    struct BodyReadingPayload: Codable {
        var date: Date
        var kg: Double
        var source: String
    }

    /// Bodyweight readings in the window, newest first. Change is latest minus the oldest
    /// reading in the window.
    func bodyMeasurements(_ arguments: WeeksArguments) -> BodyPayload {
        let weeks = arguments.clampedWeeks
        let since = calendar.date(byAdding: .weekOfYear, value: -weeks, to: now()) ?? .distantPast
        let descriptor = FetchDescriptor<BodyMeasurementModel>(
            predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let readings = store.fetch(descriptor).compactMap { model -> BodyReadingPayload? in
            guard let kg = model.bodyweightKg else { return nil }
            return BodyReadingPayload(date: model.date, kg: Self.kg(kg), source: model.source)
        }
        let cap = Self.maxSeriesSessions
        let latest = readings.first?.kg ?? store.latestBodyMeasurement()?.bodyweightKg.map { Self.kg($0) }
        let change: Double? = readings.count >= 2 ? (readings.first?.kg ?? 0) - (readings.last?.kg ?? 0) : nil
        return BodyPayload(
            weeks: weeks, latestKg: latest, changeKg: Self.kg(change), readings: Array(readings.prefix(cap)),
            truncated: readings.count > cap
        )
    }

    // MARK: - search_exercises

    struct SearchPayload: Codable {
        var exercises: [ExerciseMatchPayload]
        var truncated: Bool
    }

    struct ExerciseMatchPayload: Codable {
        var id: UUID
        var name: String
        var primary: [String]
        var secondary: [String]
        var equipment: String
        var machine: String?
        var allowed: Bool
        var reason: String?
    }

    /// Library search with the lifter's equipment verdict on every hit, so the model can pick
    /// only what `propose_*` will accept.
    func searchExercises(_ arguments: SearchArguments) throws -> SearchPayload {
        let query = (arguments.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let muscle = try arguments.muscle.map { raw -> Muscle in
            guard let muscle = Muscle(rawValue: raw) else {
                throw CoachChatToolError.badArguments("unknown muscle '\(raw)'")
            }
            return muscle
        }
        guard !query.isEmpty || muscle != nil else {
            throw CoachChatToolError.badArguments("give a muscle, a query, or both")
        }
        let cap = CoachChatToolCatalog.maxSearchResults
        let limit = min(max(arguments.limit ?? Self.defaultSearchResults, 1), cap)
        let availability = store.equipmentAvailabilityForProgram()
        let allowedOnly = arguments.allowedOnly ?? true
        // Allowed exercises first, then the library's own order — the model asked for a muscle
        // group's options, so what the lifter can actually do should come before what they can't.
        let candidates = store.exercises(matching: query, muscle: muscle, equipment: arguments.equipment)
            .filter { arguments.machine == nil || $0.machine == arguments.machine }
        var allowedMatches: [ExerciseInfo] = []
        var blockedMatches: [ExerciseInfo] = []
        for exercise in candidates {
            let verdict = availability.verdict(equipment: exercise.equipment, machine: exercise.machine)
            if verdict == .allowed {
                allowedMatches.append(exercise)
            } else if !allowedOnly {
                blockedMatches.append(exercise)
            }
        }
        let matches = allowedMatches + blockedMatches
        let exercises = matches.prefix(limit).map { exercise -> ExerciseMatchPayload in
            let verdict = availability.verdict(equipment: exercise.equipment, machine: exercise.machine)
            let reason: String? = switch verdict {
            case .allowed: nil
            case .missingType(let type): "needs \(type), not in the lifter's equipment"
            case .missingMachine(let machine): "needs a \(machine.displayName) the gym does not have"
            }
            return ExerciseMatchPayload(
                id: exercise.id, name: exercise.name, primary: exercise.primary.map(\.displayName),
                secondary: exercise.secondary.map(\.displayName), equipment: exercise.equipment,
                machine: exercise.machine, allowed: verdict == .allowed, reason: reason
            )
        }
        return SearchPayload(exercises: exercises, truncated: matches.count > limit)
    }
}
