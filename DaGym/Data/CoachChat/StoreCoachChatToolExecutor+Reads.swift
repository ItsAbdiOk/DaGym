import Foundation
import GymCore
import SwiftData

/// The structural reads: profile, routines, schedule and workouts. Each payload is a Codable
/// struct with snake_case keys, so what the model sees is exactly what a test decodes.
extension StoreCoachChatToolExecutor {
    // MARK: - get_profile

    struct ProfilePayload: Codable {
        var today: Date
        var unit: String
        var weeklyGoal: Int?
        var bodyweightKg: Double?
        var trainingGoal: String?
        var experience: String?
        var equipmentProfile: String?
        var equipmentTypes: [String]
        var restrictsMachines: Bool
        var machines: [String]
        var activeProgram: ProgramPayload?
        var routineCount: Int
        var workoutsLast4Weeks: Int

        enum CodingKeys: String, CodingKey {
            case today, unit, experience, machines
            case weeklyGoal = "weekly_goal"
            case bodyweightKg = "bodyweight_kg"
            case trainingGoal = "training_goal"
            case equipmentProfile = "equipment_profile"
            case equipmentTypes = "equipment_types"
            case restrictsMachines = "restricts_machines"
            case activeProgram = "active_program"
            case routineCount = "routine_count"
            case workoutsLast4Weeks = "workouts_last_4_weeks"
        }
    }

    struct ProgramPayload: Codable {
        var id: UUID
        var name: String
        var weeks: Int
        var currentWeek: Int?
        var routineIDs: [UUID]

        enum CodingKeys: String, CodingKey {
            case id, name, weeks
            case currentWeek = "current_week"
            case routineIDs = "routine_ids"
        }
    }

    func profile() -> ProfilePayload {
        let facts = store.lifterProfileFacts(
            unit: unit, weeklyGoal: weeklyGoal, trainingGoal: nil, now: now(), calendar: calendar
        )
        let program = store.activeProgramModel(now: now(), calendar: calendar).map { model in
            ProgramPayload(
                id: model.id, name: model.name, weeks: model.weeks,
                currentWeek: store.currentWeek(for: model, now: now(), calendar: calendar),
                routineIDs: model.routineIDs
            )
        }
        return ProfilePayload(
            today: now(), unit: unit.rawValue, weeklyGoal: facts.weeklyGoal,
            bodyweightKg: Self.kg(facts.bodyweightKg), trainingGoal: facts.goal?.rawValue,
            experience: facts.experience?.rawValue, equipmentProfile: facts.equipmentProfileName,
            equipmentTypes: facts.equipmentTypes, restrictsMachines: facts.restrictsMachines,
            machines: facts.machines, activeProgram: program, routineCount: facts.routineNames.count,
            workoutsLast4Weeks: facts.workoutsLast4Weeks ?? 0
        )
    }

    // MARK: - list_routines / get_routine

    struct RoutineSummaryPayload: Codable {
        var id: UUID
        var name: String
        var exerciseCount: Int
        var setCount: Int
        var muscles: [String]
        var rule: String
        var lastPerformed: Date?

        enum CodingKeys: String, CodingKey {
            case id, name, muscles, rule
            case exerciseCount = "exercise_count"
            case setCount = "set_count"
            case lastPerformed = "last_performed"
        }
    }

    func listRoutines() -> [RoutineSummaryPayload] {
        // One pass over finished workouts for every routine's "last performed".
        var lastPerformed: [UUID: Date] = [:]
        for workout in store.finishedWorkoutModelsNewestFirst() {
            guard let routineID = workout.routineID, lastPerformed[routineID] == nil else { continue }
            lastPerformed[routineID] = workout.startedAt
        }
        return store.routines().map { routine in
            var seen = Set<Muscle>()
            let muscles = routine.exercises.flatMap(\.primary).filter { seen.insert($0).inserted }
            return RoutineSummaryPayload(
                id: routine.id, name: routine.name, exerciseCount: routine.exercises.count,
                setCount: routine.setCount, muscles: muscles.map(\.displayName),
                rule: routine.progressionRule, lastPerformed: lastPerformed[routine.id]
            )
        }
    }

    struct RoutinePayload: Codable {
        var id: UUID
        var name: String
        var notes: String?
        var rule: String
        var exercises: [RoutineExercisePayload]
    }

    struct RoutineExercisePayload: Codable {
        var exerciseID: UUID
        var name: String
        var equipment: String
        var machine: String?
        var primary: [String]
        var sets: [PlannedSetPayload]
        var restSeconds: Int?
        var supersetGroup: Int?
        var note: String?

        enum CodingKeys: String, CodingKey {
            case name, equipment, machine, primary, sets, note
            case exerciseID = "exercise_id"
            case restSeconds = "rest_seconds"
            case supersetGroup = "superset_group"
        }
    }

    struct PlannedSetPayload: Codable {
        var kind: String
        var targetReps: Int?
        var targetRepsHigh: Int?
        var targetWeightKg: Double?
        var rpe: Double?
        var targetSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case kind, rpe
            case targetReps = "target_reps"
            case targetRepsHigh = "target_reps_high"
            case targetWeightKg = "target_weight_kg"
            case targetSeconds = "target_seconds"
        }
    }

    func routine(id arguments: RoutineArguments) throws -> RoutinePayload {
        guard let (info, drafts) = store.routineDrafts(id: arguments.routineID) else {
            throw CoachChatToolError.notFound(
                "No routine with id \(arguments.routineID.uuidString); use list_routines."
            )
        }
        let model = store.fetchRoutineModel(id: info.id)
        let exercises = zip(info.exercises, drafts).map { exercise, draft in
            RoutineExercisePayload(
                exerciseID: exercise.id, name: exercise.name, equipment: exercise.equipment,
                machine: exercise.machine, primary: exercise.primary.map(\.displayName),
                sets: draft.sets.map { set in
                    PlannedSetPayload(
                        kind: set.kind.rawValue, targetReps: set.targetReps,
                        targetRepsHigh: set.targetRepsHigh, targetWeightKg: Self.kg(set.targetWeightKg),
                        rpe: set.targetRPE, targetSeconds: set.targetSeconds
                    )
                },
                restSeconds: draft.restOverrideSeconds, supersetGroup: draft.supersetGroup,
                note: draft.note.isEmpty ? nil : draft.note
            )
        }
        let notes = model?.notes ?? ""
        return RoutinePayload(
            id: info.id, name: info.name, notes: notes.isEmpty ? nil : notes,
            rule: info.progressionRule, exercises: exercises
        )
    }

    // MARK: - get_schedule

    struct SchedulePayload: Codable {
        var days: [String: [ScheduledRoutinePayload]]
        var overrides: [ScheduleOverridePayload]
        var trainingDaysPerWeek: Int

        enum CodingKeys: String, CodingKey {
            case days, overrides
            case trainingDaysPerWeek = "training_days_per_week"
        }
    }

    struct ScheduledRoutinePayload: Codable {
        var routineID: UUID
        var name: String

        enum CodingKeys: String, CodingKey {
            case name
            case routineID = "routine_id"
        }
    }

    struct ScheduleOverridePayload: Codable {
        var date: String
        var routines: [ScheduledRoutinePayload]
    }

    /// Weekday keys are the same lowercase names `propose_schedule` takes. Overrides are the
    /// next two weeks only; a rest override is an empty list.
    func schedule() -> SchedulePayload {
        let plan = store.schedule()
        let names = Dictionary(
            store.routines().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        func payloads(_ ids: [UUID]) -> [ScheduledRoutinePayload] {
            ids.compactMap { id in names[id].map { ScheduledRoutinePayload(routineID: id, name: $0) } }
        }
        let days = Dictionary(
            plan.dayRoutines.map { ($0.key.displayName.lowercased(), payloads($0.value)) },
            uniquingKeysWith: { first, _ in first }
        )
        let today = calendar.startOfDay(for: now())
        let horizon = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        let overrides = plan.dateOverrides.compactMap { key, ids -> ScheduleOverridePayload? in
            guard let date = DateKey.date(from: key, calendar: calendar), date >= today, date <= horizon
            else { return nil }
            return ScheduleOverridePayload(date: key, routines: payloads(ids))
        }
        .sorted { $0.date < $1.date }
        return SchedulePayload(
            days: days, overrides: overrides, trainingDaysPerWeek: days.filter { !$0.value.isEmpty }.count
        )
    }

    // MARK: - get_recent_workouts / get_workout

    struct RecentWorkoutsPayload: Codable {
        var workouts: [WorkoutSummaryPayload]
        var total: Int
        var truncated: Bool
    }

    struct WorkoutSummaryPayload: Codable {
        var id: UUID
        var date: Date
        var title: String
        var durationMinutes: Int
        var sets: Int
        var volumeKg: Double
        var prCount: Int

        enum CodingKeys: String, CodingKey {
            case id, date, title, sets
            case durationMinutes = "duration_minutes"
            case volumeKg = "volume_kg"
            case prCount = "pr_count"
        }
    }

    func recentWorkouts(_ arguments: LimitArguments) -> RecentWorkoutsPayload {
        let cap = CoachChatToolCatalog.maxRecentWorkouts
        let limit = min(max(arguments.limit ?? CoachChatToolCatalog.defaultRecentWorkouts, 1), cap)
        let history = store.history()
        let workouts = history.prefix(limit).map { record in
            WorkoutSummaryPayload(
                id: record.id, date: record.date, title: record.title,
                durationMinutes: record.durationMinutes, sets: record.sets,
                volumeKg: Self.kg(record.volumeKg), prCount: record.prCount
            )
        }
        return RecentWorkoutsPayload(
            workouts: workouts, total: history.count, truncated: history.count > limit
        )
    }

    struct WorkoutPayload: Codable {
        var id: UUID
        var date: Date
        var title: String
        var durationMinutes: Int
        var notes: String?
        var exercises: [WorkoutExercisePayload]

        enum CodingKeys: String, CodingKey {
            case id, date, title, notes, exercises
            case durationMinutes = "duration_minutes"
        }
    }

    struct WorkoutExercisePayload: Codable {
        var exerciseID: UUID
        var name: String
        var sets: [LoggedSetPayload]
        var supersetGroup: Int?
        var wasSubstitution: Bool?

        enum CodingKeys: String, CodingKey {
            case name, sets
            case exerciseID = "exercise_id"
            case supersetGroup = "superset_group"
            case wasSubstitution = "was_substitution"
        }
    }

    struct LoggedSetPayload: Codable {
        var kind: String
        var weightKg: Double
        var reps: Int
        var rpe: Double?
        var durationSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case kind, reps, rpe
            case weightKg = "weight_kg"
            case durationSeconds = "duration_seconds"
        }
    }

    /// Completed sets only — a set the lifter skipped is not something they did.
    func workout(_ arguments: WorkoutArguments) throws -> WorkoutPayload {
        guard store.workout(id: arguments.workoutID) != nil else {
            throw CoachChatToolError.notFound(
                "No workout with id \(arguments.workoutID.uuidString); use get_recent_workouts."
            )
        }
        let detail = store.workoutDetail(id: arguments.workoutID)
        let minutes = detail.endedAt.map { max(0, Int($0.timeIntervalSince(detail.startedAt) / 60)) } ?? 0
        let exercises = detail.exercises.map { entry in
            WorkoutExercisePayload(
                exerciseID: entry.exercise.id, name: entry.exercise.name,
                sets: entry.sets.filter(\.isDone).map { set in
                    LoggedSetPayload(
                        kind: set.kind.rawValue, weightKg: Self.kg(set.weightKg), reps: set.reps,
                        rpe: set.effort?.rpe, durationSeconds: set.durationSeconds
                    )
                },
                supersetGroup: entry.supersetGroup, wasSubstitution: entry.wasSubstitution ? true : nil
            )
        }
        return WorkoutPayload(
            id: detail.id, date: detail.startedAt, title: detail.title, durationMinutes: minutes,
            notes: detail.notes.isEmpty ? nil : detail.notes, exercises: exercises
        )
    }
}
