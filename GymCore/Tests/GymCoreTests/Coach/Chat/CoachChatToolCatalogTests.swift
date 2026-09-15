import Foundation
import Testing

@testable import GymCore

@Suite("CoachChatToolCatalog: the tool contract is complete and encodes as the API expects")
struct CoachChatToolCatalogTests {
    @Test("every tool name is present exactly once and every name is a known case")
    func completeness() {
        let names = CoachChatToolCatalog.names
        #expect(Set(names).count == names.count)
        #expect(Set(names) == Set(CoachChatToolName.allCases.map(\.rawValue)))
        #expect(names.allSatisfy { $0 == $0.lowercased() && !$0.contains(" ") })
        for name in CoachChatToolName.allCases {
            #expect(CoachChatToolCatalog.tool(named: name.rawValue) != nil)
            #expect(!name.activityLabel.isEmpty)
        }
        #expect(CoachChatToolCatalog.tool(named: "drop_tables") == nil)
        #expect(CoachChatToolName.proposeRoutine.isProposal)
        #expect(!CoachChatToolName.getProfile.isProposal)
    }

    @Test("every schema round-trips through JSONEncoder and has the OpenAI shape")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for tool in CoachChatToolCatalog.tools {
            let data = try encoder.encode(tool)
            let decoded = try JSONDecoder().decode(CoachChatTool.self, from: data)
            #expect(decoded == tool, "\(tool.name)")
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["name"] as? String == tool.name)
            #expect(!(object["description"] as? String ?? "").isEmpty)
            let parameters = try #require(object["parameters"] as? [String: Any])
            #expect(parameters["type"] as? String == "object")
            #expect(parameters["additionalProperties"] as? Bool == false)
            #expect(parameters["properties"] is [String: Any])
            #expect(parameters["items"] == nil, "nil fields are left out")
        }
    }

    @Test("required properties exist, and array items are boxed transparently")
    func schemaShape() throws {
        for tool in CoachChatToolCatalog.tools {
            let properties = tool.parameters.properties ?? [:]
            for key in tool.parameters.required ?? [] {
                #expect(properties[key] != nil, "\(tool.name).\(key)")
            }
        }
        let routine = try #require(CoachChatToolCatalog.tool(named: "propose_routine"))
        let exercises = try #require(routine.parameters.properties?["exercises"])
        #expect(exercises.type == "array")
        let exercise = try #require(exercises.itemSchema)
        #expect(exercise.properties?["sets"]?.itemSchema?.properties?["target_reps"]?.type == "integer")
        let data = try JSONEncoder().encode(exercises)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try #require(object["items"] as? [String: Any])
        #expect(items["type"] as? String == "object")
        let search = try #require(CoachChatToolCatalog.tool(named: "search_exercises"))
        #expect(search.parameters.properties?["machine"]?.enum?.count == Machine.allCases.count)
    }

    @Test("propose_* argument objects shaped by the schema decode into the proposal types")
    func proposalArguments() throws {
        let decoder = JSONDecoder()
        let routine = """
        {"name":"Upper A","exercises":[{"exercise_name":"Bench Press","sets":[{"kind":"warmup",
        "target_reps":10,"target_weight_kg":40},{"target_reps":8,"target_weight_kg":80,"rpe":8}],
        "rest_seconds":120}],"rule":"double_progression","notes":"Push hard."}
        """
        let routineProposal = try decoder.decode(RoutineProposal.self, from: Data(routine.utf8))
        #expect(routineProposal.exercises[0].sets[0].kind == .warmup)
        #expect(routineProposal.rule == .doubleProgression)
        #expect(routineProposal.setCount == 2)

        let program = "{\"name\":\"UL\",\"goal\":\"strength\",\"days_per_week\":4}"
        let programProposal = try decoder.decode(ProgramProposal.self, from: Data(program.utf8))
        #expect(programProposal.usesTemplate)
        #expect(programProposal.goal == .strength)

        let deload = "{\"exercise_name\":\"Squat\",\"percent\":10}"
        #expect(try decoder.decode(DeloadProposal.self, from: Data(deload.utf8)).percent == 10)

        let id = UUID()
        let swap = "{\"routine_id\":\"\(id.uuidString)\",\"from_exercise_name\":\"A\","
            + "\"to_exercise_name\":\"B\"}"
        #expect(try decoder.decode(SwapProposal.self, from: Data(swap.utf8)).routineID == id)

        for name in CoachChatToolName.allCases where name.isProposal {
            let tool = try #require(CoachChatToolCatalog.tool(named: name.rawValue))
            let keys = Set(tool.parameters.properties?.keys ?? [:].keys)
            let expected: Set<String> = switch name {
            case .proposeRoutine: ["name", "exercises", "rule", "notes"]
            case .proposeProgram:
                ["name", "goal", "days_per_week", "experience", "session_minutes", "routines"]
            case .proposeSchedule: ["days"]
            case .proposeDeload: ["exercise_id", "exercise_name", "percent"]
            case .proposeSwap:
                [
                    "routine_id", "from_exercise_id", "from_exercise_name", "to_exercise_id",
                    "to_exercise_name"
                ]
            default: []
            }
            #expect(keys == expected, Comment(rawValue: name.rawValue))
        }
    }
}
