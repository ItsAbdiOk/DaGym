import Foundation
import GymCore
import Testing

@testable import DaGym

/// Every read tool answers valid JSON from the seeded store, with the numbers the two logged
/// sessions imply; the proposal tools validate against the library and the gym's stations.
@MainActor
@Suite("Coach chat tool executor")
struct CoachChatToolExecutorTests {
    @Test("every catalogue tool returns JSON or a draft on the seeded store, never an error")
    func everyToolAnswers() async throws {
        let fixture = try CoachChatToolFixture.make()
        let bench = fixture.bench.id.uuidString
        let routine = fixture.routine.id.uuidString
        let workout = try #require(fixture.store.history().first?.id.uuidString)
        let arguments: [CoachChatToolName: String] = [
            .getRoutine: #"{"routine_id":"\#(routine)"}"#,
            .getWorkout: #"{"workout_id":"\#(workout)"}"#,
            .getExerciseHistory: #"{"exercise_name":"bench press"}"#,
            .forecastE1RM: #"{"exercise_id":"\#(bench)","target_kg":120}"#,
            .searchExercises: #"{"query":"press"}"#,
            .remember: #"{"text":"Knees hurt on leg press","topic":"injury"}"#,
            .proposeRoutine: #"{"name":"Pull","exercises":[{"exercise_name":"Dumbbell Row","#
                + #""sets":[{"target_reps":10}]}]}"#,
            .proposeProgram: #"{"name":"UL","goal":"strength","days_per_week":4}"#,
            .proposeSchedule: #"{"days":{"monday":"\#(routine)"}}"#,
            .proposeDeload: #"{"exercise_id":"\#(bench)","percent":10}"#,
            .proposeSwap: #"{"routine_id":"\#(routine)","from_exercise_id":"\#(bench)","#
                + #""to_exercise_name":"Dumbbell Row"}"#,
            .agreeWithProposal: #"{"reasons":["Volume matches"],"confidence":"high"}"#
        ]
        for tool in CoachChatToolName.allCases {
            let result = try await fixture.executor.execute(
                name: tool.rawValue, argumentsJSON: arguments[tool] ?? ""
            )
            switch result {
            case .json(let text):
                #expect(!tool.isProposal, "\(tool.rawValue) should have produced a draft")
                let object = try CoachChatToolFixture.object(text)
                #expect(!object.isEmpty)
            case .draft(_, let summary):
                #expect(tool.isProposal, "\(tool.rawValue) should have produced JSON")
                let object = try CoachChatToolFixture.object(summary)
                #expect(object["draft"] is String)
            }
        }
    }

    @Test("an unknown tool and malformed arguments are errors the model can read")
    func errors() async throws {
        let fixture = try CoachChatToolFixture.make()
        await #expect(throws: CoachChatToolError.unknownTool("get_moon")) {
            try await fixture.executor.execute(name: "get_moon", argumentsJSON: "{}")
        }
        await #expect(throws: CoachChatToolError.badArguments("missing routine_id")) {
            try await fixture.executor.execute(name: "get_routine", argumentsJSON: "{}")
        }
        await #expect(throws: CoachChatToolError.self) {
            try await fixture.executor.execute(
                name: "get_exercise_history", argumentsJSON: #"{"exercise_name":"Zzz"}"#
            )
        }
    }

    @Test("get_profile states the unit, goal, equipment and stations in the lifter's words")
    func profile() async throws {
        let fixture = try CoachChatToolFixture.make(unit: .lb)
        let profile = try await fixture.call(.getProfile)
        #expect(profile["unit"] as? String == "lb")
        #expect(profile["today"] as? String == "2026-09-15")
        #expect(profile["weekly_goal"] as? Int == 2)
        #expect(profile["bodyweight_kg"] as? Double == 80)
        #expect(profile["equipment_profile"] as? String == "Home")
        #expect(profile["equipment_types"] as? [String] == ["barbell", "dumbbell", "machine"])
        #expect(profile["restricts_machines"] as? Bool == true)
        #expect(profile["machines"] as? [String] == ["Leg Curl"])
        #expect(profile["routine_count"] as? Int == 1)
        #expect(profile["workouts_last_4_weeks"] as? Int == 2)
        #expect(profile["active_program"] == nil)
    }

    @Test("list_routines and get_routine read the plan back with ids the proposals accept")
    func routines() async throws {
        let fixture = try CoachChatToolFixture.make()
        let result = try await fixture.executor.execute(name: "list_routines", argumentsJSON: "")
        guard case .json(let text) = result else {
            Issue.record("expected JSON")
            return
        }
        let object = try CoachChatToolFixture.object(text)
        let routines = try #require(object["routines"] as? [[String: Any]])
        #expect(routines.count == 1)
        #expect(routines[0]["name"] as? String == "Push")
        #expect(routines[0]["exercise_count"] as? Int == 2)
        #expect(routines[0]["set_count"] as? Int == 6)
        #expect(routines[0]["muscles"] as? [String] == ["Chest", "Lats"])
        #expect(routines[0]["last_performed"] as? String == "2026-09-14")

        let id = fixture.routine.id.uuidString
        let routine = try await fixture.call(.getRoutine, #"{"routine_id":"\#(id)"}"#)
        let exercises = try #require(routine["exercises"] as? [[String: Any]])
        #expect(exercises.map { $0["name"] as? String } == ["Bench Press", "Dumbbell Row"])
        let sets = try #require(exercises[0]["sets"] as? [[String: Any]])
        #expect(sets.count == 3)
        #expect(sets[0]["target_reps"] as? Int == 8)
        #expect(sets[0]["target_weight_kg"] as? Double == 60)
        #expect(sets[0]["kind"] as? String == "working")
    }

    @Test("get_schedule names the weekday routines and counts training days")
    func schedule() async throws {
        let fixture = try CoachChatToolFixture.make()
        let schedule = try await fixture.call(.getSchedule)
        let days = try #require(schedule["days"] as? [String: [[String: Any]]])
        #expect(Set(days.keys) == ["monday", "thursday"])
        #expect(days["monday"]?.first?["name"] as? String == "Push")
        #expect(schedule["training_days_per_week"] as? Int == 2)
        #expect((schedule["overrides"] as? [Any])?.isEmpty == true)
    }

    @Test("get_recent_workouts caps and flags truncation; get_workout lists done sets only")
    func workouts() async throws {
        let fixture = try CoachChatToolFixture.make()
        let recent = try await fixture.call(.getRecentWorkouts, #"{"limit":1}"#)
        let workouts = try #require(recent["workouts"] as? [[String: Any]])
        #expect(workouts.count == 1)
        #expect(recent["total"] as? Int == 2)
        #expect(recent["truncated"] as? Bool == true)
        #expect(workouts[0]["date"] as? String == "2026-09-14")
        #expect(workouts[0]["sets"] as? Int == 6)
        #expect(workouts[0]["volume_kg"] as? Double == 3840)

        let id = try #require(workouts[0]["id"] as? String)
        let workout = try await fixture.call(.getWorkout, #"{"workout_id":"\#(id)"}"#)
        let exercises = try #require(workout["exercises"] as? [[String: Any]])
        #expect(exercises.count == 2)
        let sets = try #require(exercises[0]["sets"] as? [[String: Any]])
        #expect(sets.map { $0["weight_kg"] as? Double } == [80, 80, 80])
        #expect(workout["duration_minutes"] as? Int == 45)
    }

    @Test("get_exercise_history: newest session first, best e1RM per session, 12-week change")
    func exerciseHistory() async throws {
        let fixture = try CoachChatToolFixture.make()
        let history = try await fixture.call(.getExerciseHistory, #"{"exercise_name":"Bench Press"}"#)
        #expect(history["name"] as? String == "Bench Press")
        let sessions = try #require(history["sessions"] as? [[String: Any]])
        #expect(sessions.map { $0["date"] as? String } == ["2026-09-14", "2026-09-07"])
        let expectedBest = (OneRepMax.estimate(weight: 80, reps: 8) ?? 0)
        #expect(sessions[0]["best_e1rm_kg"] as? Double == (expectedBest * 2).rounded() / 2)
        #expect(history["truncated"] as? Bool == false)
        let summary = try #require(history["last_12_weeks"] as? [String: Any])
        #expect(summary["sessions"] as? Int == 2)
        #expect(summary["top_weight_kg"] as? Double == 80)
        #expect((summary["change_kg"] as? Double ?? 0) > 0)
    }

    @Test("forecast_e1rm wires ProgressForecast and reports the caveat for two sessions")
    func forecast() async throws {
        let fixture = try CoachChatToolFixture.make()
        let forecast = try await fixture.call(
            .forecastE1RM, #"{"exercise_id":"\#(fixture.bench.id.uuidString)","target_kg":120}"#
        )
        #expect(forecast["caveat"] as? String == ProgressForecast.Caveat.tooFewSessions.rawValue)
        #expect(forecast["sessions"] as? Int == 2)
        #expect(forecast["target_kg"] as? Double == 120)
        #expect(forecast["reach_date"] == nil)
        #expect((forecast["caveat_text"] as? String)?.contains("too few") == true)

        let never = try await fixture.call(.forecastE1RM, #"{"exercise_name":"Leg Press","target_kg":200}"#)
        #expect(never["caveat"] as? String == "no_sessions")
    }

    @Test("get_weekly_volume lists every week, current first, with the sessions' totals")
    func weeklyVolume() async throws {
        let fixture = try CoachChatToolFixture.make()
        let volume = try await fixture.call(.getWeeklyVolume, #"{"weeks":3}"#)
        let weeks = try #require(volume["weeks"] as? [[String: Any]])
        #expect(weeks.map { $0["week_start"] as? String } == ["2026-09-14", "2026-09-07", "2026-08-31"])
        #expect(weeks.map { $0["sessions"] as? Int } == [1, 1, 0])
        #expect(weeks[0]["volume_kg"] as? Double == 3840)
        #expect(weeks[0]["minutes"] as? Int == 45)
    }

    @Test("get_muscle_volume grades every muscle against the coverage floor per week")
    func muscleVolume() async throws {
        let fixture = try CoachChatToolFixture.make()
        let volume = try await fixture.call(.getMuscleVolume, #"{"weeks":2}"#)
        #expect(volume["floor_sets_per_week"] as? Double == 2)
        let muscles = try #require(volume["muscles"] as? [[String: Any]])
        let chest = try #require(muscles.first { $0["muscle"] as? String == "Chest" })
        #expect(chest["total_sets"] as? Double == 6)
        #expect(chest["sets_per_week"] as? Double == 3)
        #expect(chest["status"] as? String == "ok")
        let quads = try #require(muscles.first { $0["muscle"] as? String == "Quads" })
        #expect(quads["status"] as? String == "untrained")
    }

    @Test("get_personal_records returns raw record numbers, optionally for one exercise")
    func personalRecords() async throws {
        let fixture = try CoachChatToolFixture.make()
        let all = try await fixture.call(.getPersonalRecords)
        let exercises = try #require(all["exercises"] as? [[String: Any]])
        #expect(exercises.map { $0["name"] as? String } == ["Bench Press", "Dumbbell Row"])
        let only = try await fixture.call(.getPersonalRecords, #"{"exercise_name":"Bench Press"}"#)
        let bench = try #require((only["exercises"] as? [[String: Any]])?.first)
        let records = try #require(bench["records"] as? [[String: Any]])
        let kinds = Set(records.compactMap { $0["kind"] as? String })
        #expect(kinds.contains("e1rm"))
        #expect(kinds.contains("max_weight"))
        #expect(records.first { $0["kind"] as? String == "max_weight" }?["weight_kg"] as? Double == 80)
    }

    @Test("get_adherence counts planned versus kept per block and the goal streak")
    func adherence() async throws {
        let fixture = try CoachChatToolFixture.make()
        let adherence = try await fixture.call(.getAdherence, #"{"weeks":2}"#)
        #expect(adherence["planned"] as? Int == 4)
        #expect(adherence["kept"] as? Int == 2)
        #expect(adherence["percent"] as? Int == 50)
        #expect(adherence["weekly_goal"] as? Int == 2)
        let blocks = try #require(adherence["per_week"] as? [[String: Any]])
        #expect(blocks.count == 2)
        #expect(blocks[0]["week_start"] as? String == "2026-09-09")
        #expect(blocks.map { $0["planned"] as? Int } == [2, 2])
        #expect(blocks.map { $0["kept"] as? Int } == [1, 1])
    }

    @Test("get_recovery reports spent muscles and the ones ready to train")
    func recovery() async throws {
        let fixture = try CoachChatToolFixture.make()
        let recovery = try await fixture.call(.getRecovery)
        let muscles = try #require(recovery["muscles"] as? [[String: Any]])
        let names = muscles.compactMap { $0["muscle"] as? String }
        #expect(names.contains("Chest"))
        #expect(names.contains("Lats"))
        let ready = try #require(recovery["ready"] as? [String])
        #expect(ready.contains("Quads"))
        #expect((recovery["untrained_this_week"] as? [String])?.contains("Calves") == true)
    }

    @Test("get_body_measurements: latest reading and change over the window")
    func bodyMeasurements() async throws {
        let fixture = try CoachChatToolFixture.make()
        fixture.store.logBodyweight(kg: 82.5, date: fixture.now.addingTimeInterval(-20 * 86_400))
        let body = try await fixture.call(.getBodyMeasurements, #"{"weeks":4}"#)
        #expect(body["latest_kg"] as? Double == 80)
        #expect(body["change_kg"] as? Double == -2.5)
        let readings = try #require(body["readings"] as? [[String: Any]])
        #expect(readings.map { $0["date"] as? String } == ["2026-09-14", "2026-08-26"])
        #expect(body["truncated"] as? Bool == false)
    }
}
