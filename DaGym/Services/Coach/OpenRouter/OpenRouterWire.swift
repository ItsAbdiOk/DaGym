import Foundation
import GymCore

/// The OpenAI-compatible chat-completions surface OpenRouter speaks, as Codable values: the
/// request we POST, the SSE chunks that stream back, the error envelope, and the public models
/// list. Every key is spelt out in `CodingKeys` rather than via a snake-case strategy because
/// `JSONValue` carries tool JSON-schemas whose own keys (`maxItems`, `targetReps`) must not be
/// rewritten on the way out.
enum OpenRouterWire {
    // MARK: - Request

    struct ChatRequest: Codable, Equatable, Sendable {
        var model: String
        var messages: [Message]
        var tools: [ToolDefinition]?
        /// `"auto"` (default), `"none"` to force a text answer, `"required"` to force a call.
        var toolChoice: String?
        var stream = true
        var streamOptions: StreamOptions? = StreamOptions(includeUsage: true)
        var maxTokens: Int?
        var temperature: Double?
        /// OpenRouter's unified reasoning control. A chat turn that reads three tools and
        /// answers does not need deep thinking; `low` cut each round from ~18 s to a few.
        var reasoning: Reasoning? = Reasoning(effort: "low")

        enum CodingKeys: String, CodingKey {
            case model, messages, tools, stream, temperature, reasoning
            case toolChoice = "tool_choice"
            case streamOptions = "stream_options"
            case maxTokens = "max_tokens"
        }
    }

    struct Reasoning: Codable, Equatable, Sendable {
        var effort: String
    }

    struct StreamOptions: Codable, Equatable, Sendable {
        var includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    enum Role: String, Codable, Sendable {
        case system, user, assistant, tool
    }

    /// One transcript entry. Assistant turns that called tools carry `toolCalls` (and often no
    /// `content`); tool results carry the `toolCallId` they answer.
    struct Message: Codable, Equatable, Sendable {
        var role: Role
        var content: String?
        var toolCalls: [ToolCall]?
        var toolCallId: String?

        init(role: Role, content: String?, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil) {
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
            self.toolCallId = toolCallId
        }

        static func system(_ text: String) -> Message { Message(role: .system, content: text) }
        static func user(_ text: String) -> Message { Message(role: .user, content: text) }
        static func assistant(_ text: String?, toolCalls: [ToolCall]? = nil) -> Message {
            Message(role: .assistant, content: text, toolCalls: toolCalls)
        }
        static func tool(callID: String, content: String) -> Message {
            Message(role: .tool, content: content, toolCallId: callID)
        }

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolCallId = "tool_call_id"
        }
    }

    /// A completed tool call as it is echoed back in the transcript.
    struct ToolCall: Codable, Equatable, Sendable {
        var id: String
        var type = "function"
        var function: FunctionCall
    }

    struct FunctionCall: Codable, Equatable, Sendable {
        var name: String
        /// A JSON document, as the model wrote it.
        var arguments: String
    }

    /// `{"type":"function","function":{name,description,parameters}}`.
    struct ToolDefinition: Codable, Equatable, Sendable {
        var type = "function"
        var function: FunctionDefinition

        init(name: String, description: String, parameters: JSONValue) {
            function = FunctionDefinition(name: name, description: description, parameters: parameters)
        }

        /// Wraps any Encodable JSON-schema value (GymCore's catalogue structs) by encoding it
        /// once and reading it back as a `JSONValue`, so the wire type never depends on them.
        init(name: String, description: String, schema: some Encodable) throws {
            let data = try JSONEncoder().encode(schema)
            let parameters = try JSONDecoder().decode(JSONValue.self, from: data)
            self.init(name: name, description: description, parameters: parameters)
        }
    }

    /// The whole catalogue as OpenRouter wants it. Throws only if a schema fails to encode,
    /// which the GymCore round-trip test rules out.
    static func toolDefinitions(
        _ tools: [CoachChatTool] = CoachChatToolCatalog.tools
    ) throws -> [ToolDefinition] {
        try tools.map {
            try ToolDefinition(name: $0.name, description: $0.description, schema: $0.parameters)
        }
    }

    struct FunctionDefinition: Codable, Equatable, Sendable {
        var name: String
        var description: String
        var parameters: JSONValue
    }

    // MARK: - Streaming response

    /// One `data:` line of the SSE stream. The last chunk usually has no choices and carries
    /// `usage`; a failure mid-stream arrives as a chunk-shaped `error` instead.
    struct StreamChunk: Decodable, Sendable {
        var id: String?
        var choices: [StreamChoice]?
        var usage: Usage?
        var error: ErrorBody?
    }

    struct StreamChoice: Decodable, Sendable {
        var index: Int?
        var delta: StreamDelta?
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    struct StreamDelta: Decodable, Sendable {
        var role: String?
        var content: String?
        var toolCalls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }

    /// A fragment of one tool call: `id` and `function.name` arrive on the first fragment for
    /// that `index`, `function.arguments` chunks on every fragment, concatenated in order.
    struct ToolCallDelta: Decodable, Sendable {
        var index: Int
        var id: String?
        var function: FunctionDelta?
    }

    struct FunctionDelta: Decodable, Sendable {
        var name: String?
        var arguments: String?
    }

    struct Usage: Codable, Equatable, Sendable {
        var promptTokens: Int
        var completionTokens: Int
        var totalTokens: Int?
        /// USD, reported when the request asked for usage accounting.
        var cost: Double?

        enum CodingKeys: String, CodingKey {
            case cost
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    /// What `OpenRouterClient.stream` yields, one per meaningful chunk.
    enum StreamEvent: Equatable, Sendable {
        case text(String)
        case toolCallDelta(index: Int, id: String?, name: String?, argumentsChunk: String)
        case finished(reason: String?, usage: Usage?)
    }

    // MARK: - Errors

    /// `{"error":{"code":401,"message":"…","metadata":{…}}}` — the body of a non-2xx reply, and
    /// also what a chunk carries when the upstream provider fails after the stream opened.
    struct ErrorEnvelope: Decodable, Sendable {
        var error: ErrorBody
    }

    struct ErrorBody: Decodable, Sendable {
        var code: Int?
        var message: String

        enum CodingKeys: String, CodingKey { case code, message }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decodeIfPresent(String.self, forKey: .message) ?? "Unknown error"
            // OpenRouter sends the code as a number; some upstreams echo a string.
            if let number = try? container.decodeIfPresent(Int.self, forKey: .code) {
                code = number
            } else {
                code = (try? container.decodeIfPresent(String.self, forKey: .code)).flatMap { Int($0) }
            }
        }
    }

    // MARK: - Models list

    struct ModelsResponse: Decodable, Sendable {
        var data: [Model]
    }

    /// One row of GET /api/v1/models. Pricing is USD per token, as decimal strings.
    struct Model: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var description: String?
        var contextLength: Int?
        var pricing: Pricing?
        var supportedParameters: [String]?

        /// Whether the row can take our `tools` definitions at all.
        var supportsTools: Bool { supportedParameters?.contains("tools") ?? false }

        enum CodingKeys: String, CodingKey {
            case id, name, description, pricing
            case contextLength = "context_length"
            case supportedParameters = "supported_parameters"
        }
    }

    struct Pricing: Codable, Equatable, Sendable {
        var prompt: String?
        var completion: String?

        /// USD per one million prompt tokens, for the picker ("$2.00 / 1M in").
        var promptUSDPerMillion: Decimal? { Self.perMillion(prompt) }
        var completionUSDPerMillion: Decimal? { Self.perMillion(completion) }

        private static func perMillion(_ perToken: String?) -> Decimal? {
            guard let perToken, let value = Decimal(string: perToken) else { return nil }
            return value * 1_000_000
        }
    }
}
