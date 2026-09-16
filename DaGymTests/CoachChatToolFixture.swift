import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// A store with a bench-press routine, a leg-press exercise the gym does not have, a schedule
/// and two logged sessions a week apart, plus the executor pinned to a fixed `now` — what every
/// coach-chat tool test reads from.
@MainActor
struct CoachChatToolFixture {
    let store: WorkoutStore
    let executor: StoreCoachChatToolExecutor
    let bench: ExerciseInfo
    let row: ExerciseInfo
    let legPress: ExerciseInfo
    let routine: RoutineInfo
    /// Tuesday 2026-09-15, midday.
    let now: Date
    let calendar: Calendar

    static func make(unit: WeightUnit = .kg) throws -> CoachChatToolFixture {
        let store = try makeStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12)) ?? Date()

        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let row = store.createCustomExercise(
            name: "Dumbbell Row", primary: [.lats], equipment: "dumbbell", style: .weightReps
        )
        let legPress = store.createCustomExercise(
            name: "Leg Press", primary: [.quads], equipment: "machine", style: .weightReps,
            machine: Machine.legPress.rawValue
        )
        store.createProfile(
            name: "Home", isActive: true, availableEquipment: ["barbell", "dumbbell", "machine"],
            plateStock: PlateStock.standardKg, restrictsMachines: true,
            availableMachines: [Machine.legCurl.rawValue]
        )
        let sets = (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60) }
        let routine = store.saveRoutine(
            id: nil, name: "Push", exercises: [
                RoutineExerciseDraft(exerciseID: bench.id, sets: sets),
                RoutineExerciseDraft(exerciseID: row.id, sets: sets)
            ]
        )
        store.saveSchedule(WeeklySchedule(days: [.monday: routine.id, .thursday: routine.id]))
        store.logBodyweight(kg: 80, date: now.addingTimeInterval(-86_400))

        for (daysAgo, weight) in [(8, 77.5), (1, 80.0)] {
            let date = now.addingTimeInterval(-Double(daysAgo) * 86_400)
            let session = store.startBackfill(date: date, durationMinutes: 45, routineID: routine.id)
            for exercise in session.exercises.indices {
                for index in session.exercises[exercise].sets.indices {
                    session.exercises[exercise].sets[index].weightKg = weight
                    session.exercises[exercise].sets[index].reps = 8
                    session.exercises[exercise].sets[index].isDone = true
                }
            }
            _ = store.finish(session: session)
        }
        let executor = StoreCoachChatToolExecutor(
            store: store, unit: unit, weeklyGoal: 2, calendar: calendar, now: { now }
        )
        return CoachChatToolFixture(
            store: store, executor: executor, bench: bench, row: row, legPress: legPress, routine: routine,
            now: now, calendar: calendar
        )
    }

    /// Runs a tool and returns its JSON object as a dictionary.
    func call(_ name: CoachChatToolName, _ arguments: String = "{}") async throws -> [String: Any] {
        let result = try await executor.execute(name: name.rawValue, argumentsJSON: arguments)
        guard case .json(let text) = result else {
            throw CoachChatToolError.badArguments("\(name.rawValue) returned a draft, not JSON")
        }
        return try Self.object(text)
    }

    func draft(_ name: CoachChatToolName, _ arguments: String) async throws -> CoachChatDraft {
        let result = try await executor.execute(name: name.rawValue, argumentsJSON: arguments)
        guard case .draft(let draft, let summary) = result else {
            throw CoachChatToolError.badArguments("expected a draft")
        }
        let object = try Self.object(summary)
        #expect(object["summary"] as? String == draft.summary)
        return draft
    }

    static func object(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }
}
