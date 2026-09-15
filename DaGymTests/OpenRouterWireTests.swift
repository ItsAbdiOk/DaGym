import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("OpenRouter wire types")
struct OpenRouterWireTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("a text delta chunk decodes to its content")
    func textChunk() throws {
        let chunk = try decode(OpenRouterWire.StreamChunk.self, FakeOpenRouterTransport.text("Hi"))
        #expect(chunk.choices?.first?.delta?.content == "Hi")
        #expect(chunk.choices?.first?.finishReason == nil)
        #expect(chunk.usage == nil)
    }

    @Test("tool-call fragments keep index, id, name and argument chunks")
    func toolCallChunk() throws {
        let first = try decode(
            OpenRouterWire.StreamChunk.self,
            FakeOpenRouterTransport.toolDelta(index: 0, id: "call_1", name: "get_profile", arguments: "{\\\"")
        )
        let call = try #require(first.choices?.first?.delta?.toolCalls?.first)
        #expect(call.index == 0)
        #expect(call.id == "call_1")
        #expect(call.function?.name == "get_profile")
        #expect(call.function?.arguments == "{\"")

        let later = try decode(
            OpenRouterWire.StreamChunk.self, FakeOpenRouterTransport.toolDelta(index: 0, arguments: "}")
        )
        let fragment = try #require(later.choices?.first?.delta?.toolCalls?.first)
        #expect(fragment.id == nil)
        #expect(fragment.function?.name == nil)
        #expect(fragment.function?.arguments == "}")
    }

    @Test("the usage chunk has empty choices and token counts plus cost")
    func usageChunk() throws {
        let chunk = try decode(
            OpenRouterWire.StreamChunk.self,
            FakeOpenRouterTransport.usage(prompt: 120, completion: 30, cost: 0.0012)
        )
        #expect(chunk.choices?.isEmpty == true)
        #expect(chunk.usage == OpenRouterWire.Usage(promptTokens: 120, completionTokens: 30, cost: 0.0012))
    }

    @Test("an error envelope decodes with numeric or string codes")
    func errorEnvelope() throws {
        let numeric = try decode(
            OpenRouterWire.ErrorEnvelope.self, #"{"error":{"code":402,"message":"Insufficient credits"}}"#
        )
        #expect(numeric.error.code == 402)
        #expect(numeric.error.message == "Insufficient credits")
        let stringy = try decode(
            OpenRouterWire.ErrorEnvelope.self,
            #"{"error":{"code":"429","message":"slow down","metadata":{}}}"#
        )
        #expect(stringy.error.code == 429)
        let bare = try decode(OpenRouterWire.StreamChunk.self, #"{"error":{"message":"upstream died"}}"#)
        #expect(bare.error?.message == "upstream died")
        #expect(bare.error?.code == nil)
    }

    @Test("the models list decodes pricing strings into USD per million tokens")
    func modelsList() throws {
        let json = """
        {"data":[{"id":"anthropic/claude-sonnet-5","name":"Anthropic: Claude Sonnet 5",
          "description":"Sonnet 5","context_length":1000000,
          "pricing":{"prompt":"0.000002","completion":"0.00001","web_search":"0.01"},
          "top_provider":{"max_completion_tokens":128000},
          "supported_parameters":["tools","tool_choice","max_tokens"]},
         {"id":"openai/gpt-oss-20b:free","name":"Free thing","pricing":{"prompt":"0","completion":"0"}}]}
        """
        let models = try decode(OpenRouterWire.ModelsResponse.self, json).data
        #expect(models.count == 2)
        let sonnet = try #require(models.first)
        #expect(sonnet.id == CoachChatConfiguration.defaultModelID)
        #expect(sonnet.contextLength == 1_000_000)
        #expect(sonnet.supportsTools)
        #expect(sonnet.pricing?.promptUSDPerMillion == Decimal(2))
        #expect(sonnet.pricing?.completionUSDPerMillion == Decimal(10))
        let free = try #require(models.last)
        #expect(free.supportsTools == false)
        #expect(free.pricing?.promptUSDPerMillion == 0)
    }

    @Test("a chat request encodes snake_case keys, the tool role and stream options")
    func chatRequestEncodes() throws {
        let tool = OpenRouterWire.ToolDefinition(
            name: "get_profile", description: "Profile",
            parameters: .object(["type": .string("object"), "properties": .object([:])])
        )
        let request = OpenRouterWire.ChatRequest(
            model: "anthropic/claude-sonnet-5",
            messages: [
                .system("You are a coach."), .user("Hi"),
                .assistant(nil, toolCalls: [
                    OpenRouterWire.ToolCall(
                        id: "call_1", function: .init(name: "get_profile", arguments: "{}")
                    )
                ]),
                .tool(callID: "call_1", content: #"{"unit":"kg"}"#)
            ],
            tools: [tool], toolChoice: "none", maxTokens: 512
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try #require(String(data: try encoder.encode(request), encoding: .utf8))
        #expect(json.contains(#""stream":true"#))
        #expect(json.contains(#""stream_options":{"include_usage":true}"#))
        #expect(json.contains(#""tool_choice":"none""#))
        #expect(json.contains(#""max_tokens":512"#))
        #expect(json.contains(#""role":"tool","tool_call_id":"call_1""#))
        let calls = #""tool_calls":[{"function":{"arguments":"{}","name":"get_profile"},"id":"call_1","#
            + #""type":"function"}]"#
        #expect(json.contains(calls))
        let tools = #""tools":[{"function":{"description":"Profile","name":"get_profile","#
            + #""parameters":{"properties":{},"type":"object"}},"type":"function"}]"#
        #expect(json.contains(tools))
        #expect(!json.contains("toolCallId"))

        let decoded = try JSONDecoder().decode(OpenRouterWire.ChatRequest.self, from: Data(json.utf8))
        #expect(decoded == request)
    }

    @Test("JSONValue round-trips nested schemas without renaming keys or turning ints into doubles")
    func jsonValueRoundTrip() throws {
        let json = #"{"maxItems":3,"minimum":1.5,"required":["targetReps"],"nested":{"ok":true,"none":null}}"#
        let value = try decode(OpenRouterWire.JSONValue.self, json)
        #expect(value["maxItems"] == .number(3))
        #expect(value["required"] == .array([.string("targetReps")]))
        #expect(value["nested"]?["none"] == .null)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let out = try #require(String(data: try encoder.encode(value), encoding: .utf8))
        #expect(
            out == #"{"maxItems":3,"minimum":1.5,"nested":{"none":null,"ok":true},"required":["targetReps"]}"#
        )
    }

    @Test("every catalogue tool maps to a function definition with its schema intact")
    func catalogueMaps() throws {
        let definitions = try OpenRouterWire.toolDefinitions()
        #expect(definitions.count == CoachChatToolCatalog.tools.count)
        #expect(Set(definitions.map(\.function.name)) == Set(CoachChatToolCatalog.names))
        let profile = try #require(definitions.first { $0.function.name == "get_profile" })
        #expect(profile.type == "function")
        #expect(profile.function.parameters["type"]?.stringValue == "object")
        let schema = try #require(CoachChatToolCatalog.tool(named: "propose_routine")).parameters
        let expected = try JSONEncoder().encode(schema)
        let routine = try #require(definitions.first { $0.function.name == "propose_routine" })
        let mapped = try JSONDecoder().decode(OpenRouterWire.JSONValue.self, from: expected)
        #expect(routine.function.parameters == mapped)
    }
}
