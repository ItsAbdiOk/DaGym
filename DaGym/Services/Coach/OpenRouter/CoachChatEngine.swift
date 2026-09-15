import Foundation
import GymCore
import os

/// One chat thread with the cloud coach: the transcript the screen renders, the wire transcript
/// the model sees, and the agent loop between them — stream a reply, run every tool it asked
/// for, send the results back, repeat (at most `maxToolRounds` times), then show the answer.
/// Tool failures go back to the model as `{"error": …}`; only transport failures reach
/// `lastError`. Cancelling leaves what was streamed plus a "stopped" marker.
@MainActor
@Observable
final class CoachChatEngine {
    static let maxToolRounds = 8

    private static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "coachChat")

    let threadID: UUID
    private(set) var messages: [CoachChatMessage]
    private(set) var drafts: [CoachChatDraft]
    private(set) var isStreaming = false
    private(set) var lastError: OpenRouterError?
    private(set) var usage: CoachChatUsage

    private let client: OpenRouterClient
    private let executor: any CoachChatToolExecutor
    private let configuration: CoachChatConfiguration
    private let systemPrompt: String
    private let tools: [OpenRouterWire.ToolDefinition]
    private let archive: CoachChatArchive?
    private let clock: @Sendable () -> Date
    private let createdAt: Date
    /// What the model sees: system prompt is prepended per request; tool calls and results stay
    /// so later turns can build on earlier lookups. Rebuilt from text only on restore.
    private var wire: [OpenRouterWire.Message] = []
    private var turn: Task<Void, Never>?

    /// `systemPrompt` is `CoachChatPrompt.system(...)` and `tools` is
    /// `OpenRouterWire.toolDefinitions()` — both built by the caller so a test can hand in a
    /// one-tool catalogue and a fixed prompt.
    init(
        client: OpenRouterClient,
        executor: any CoachChatToolExecutor,
        configuration: CoachChatConfiguration,
        systemPrompt: String,
        tools: [OpenRouterWire.ToolDefinition],
        thread: CoachChatThread? = nil,
        archive: CoachChatArchive? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.executor = executor
        self.configuration = configuration
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.archive = archive
        self.clock = clock
        threadID = thread?.id ?? UUID()
        createdAt = thread?.createdAt ?? clock()
        messages = thread?.messages ?? []
        drafts = thread?.drafts ?? []
        usage = thread?.usage ?? CoachChatUsage()
        wire = Self.wireTranscript(from: messages)
    }

    /// The thread as the archive stores it.
    func snapshot() -> CoachChatThread {
        CoachChatThread(
            id: threadID, createdAt: createdAt, updatedAt: messages.last?.sentAt ?? createdAt,
            messages: messages, drafts: drafts, usage: usage
        )
    }

    // MARK: - Sending

    /// Sends one user message and runs the loop to its final text. Returns when the reply is
    /// complete, failed or stopped; the screen watches `messages` for the streaming bubble.
    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        lastError = nil
        isStreaming = true
        messages.append(.user(trimmed, at: clock()))
        wire.append(.user(trimmed))
        let task = Task { await runTurn() }
        turn = task
        await task.value
        turn = nil
        isStreaming = false
        persist()
    }

    /// Stops the stream (and any tool still running) at the next opportunity.
    func cancel() {
        turn?.cancel()
    }

    private func runTurn() async {
        let wireBase = wire.count
        for round in 0...Self.maxToolRounds {
            // Past the round cap the model must answer in words.
            let forceText = round == Self.maxToolRounds
            let request = OpenRouterWire.ChatRequest(
                model: configuration.modelID, messages: [.system(systemPrompt)] + wire,
                tools: tools.isEmpty ? nil : tools, toolChoice: forceText ? "none" : nil,
                maxTokens: configuration.maxTokens
            )
            let reply: Reply
            do {
                reply = try await consume(request)
            } catch is CancellationError {
                return abandonTurn(from: wireBase, stopped: true)
            } catch let error as OpenRouterError {
                lastError = error
                return abandonTurn(from: wireBase, stopped: false)
            } catch {
                lastError = .network(error)
                return abandonTurn(from: wireBase, stopped: false)
            }
            wire.append(.assistant(
                reply.text.isEmpty ? nil : reply.text, toolCalls: reply.calls.isEmpty ? nil : reply.calls
            ))
            if reply.calls.isEmpty { return }
            for call in reply.calls {
                if Task.isCancelled { return abandonTurn(from: wireBase, stopped: true) }
                let content = await execute(call)
                wire.append(.tool(callID: call.id, content: content))
            }
        }
    }

    /// The streamed part of one model reply, with tool-call fragments already concatenated.
    private struct Reply {
        var text = ""
        var calls: [OpenRouterWire.ToolCall] = []
    }

    private func consume(_ request: OpenRouterWire.ChatRequest) async throws -> Reply {
        var reply = Reply()
        var bubbleIndex: Int?
        var calls: [Int: OpenRouterWire.ToolCall] = [:]
        for try await event in client.stream(request: request) {
            switch event {
            case .text(let text):
                reply.text += text
                if let bubbleIndex {
                    messages[bubbleIndex].text = reply.text
                } else {
                    bubbleIndex = messages.count
                    messages.append(.assistant(reply.text, at: clock()))
                }
            case .toolCallDelta(let index, let id, let name, let chunk):
                var call = calls[index] ?? OpenRouterWire.ToolCall(
                    id: "", function: OpenRouterWire.FunctionCall(name: "", arguments: "")
                )
                if let id { call.id = id }
                if let name { call.function.name = name }
                call.function.arguments += chunk
                calls[index] = call
            case .finished(let reason, let turnUsage):
                if let turnUsage { usage.add(turnUsage) }
                if reason == "length", let bubbleIndex { messages[bubbleIndex].isStopped = true }
            }
        }
        // A cancelled consumer sees the stream end rather than throw; make it throw here so the
        // turn is abandoned instead of a half-reply being sent back as if it were whole.
        try Task.checkCancellation()
        reply.calls = calls.keys.sorted().compactMap { calls[$0] }.filter { !$0.function.name.isEmpty }
        return reply
    }

    /// Runs one tool call, showing an activity chip while it runs, and returns what the model
    /// gets back: the tool's JSON, the draft's compact summary, or `{"error": …}`.
    private func execute(_ call: OpenRouterWire.ToolCall) async -> String {
        let chipIndex = messages.count
        messages.append(.tool(call.function.name, at: clock()))
        do {
            let result = try await executor.execute(
                name: call.function.name, argumentsJSON: call.function.arguments
            )
            switch result {
            case .json(let json):
                return json
            case .draft(let draft, let summaryJSON):
                drafts.append(draft)
                messages.append(.draft(index: drafts.count - 1, summary: draft.summary, at: clock()))
                return summaryJSON
            }
        } catch {
            messages[chipIndex].isToolError = true
            let name = call.function.name
            let reason = error.localizedDescription
            Self.logger.notice("Tool \(name, privacy: .public) failed: \(reason, privacy: .public)")
            return Self.errorJSON(error.localizedDescription)
        }
    }

    static func errorJSON(_ message: String) -> String {
        guard let data = try? JSONEncoder().encode(["error": message]),
              let json = String(data: data, encoding: .utf8)
        else { return #"{"error":"Tool failed."}"# }
        return json
    }

    /// Rolls the wire transcript back to the user message so no assistant tool call is left
    /// without its result (the API rejects that), keeping any text that did stream as context.
    private func abandonTurn(from wireBase: Int, stopped: Bool) {
        let partial = messages.last.flatMap { $0.role == .assistant ? $0.text : nil } ?? ""
        wire.removeSubrange(wireBase...)
        if !partial.isEmpty { wire.append(.assistant(partial)) }
        guard stopped else { return }
        if let last = messages.indices.last, messages[last].role == .assistant {
            messages[last].isStopped = true
        } else {
            var marker = CoachChatMessage.assistant("", at: clock())
            marker.isStopped = true
            messages.append(marker)
        }
    }

    private func persist() {
        guard let archive else { return }
        do {
            try archive.save(snapshot())
        } catch {
            Self.logger.error("Couldn't save chat thread: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Text-only reconstruction for a restored thread; tool chatter from earlier sessions isn't
    /// replayed, so the model re-reads what it needs.
    private static func wireTranscript(from messages: [CoachChatMessage]) -> [OpenRouterWire.Message] {
        messages.compactMap { message in
            switch message.role {
            case .user: .user(message.text)
            case .assistant: message.text.isEmpty ? nil : .assistant(message.text)
            case .tool, .draft: nil
            }
        }
    }
}
