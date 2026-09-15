import Foundation
import GymCore
import Testing

@testable import DaGym

/// Answers tool calls from a script and records what it was asked, so the agent loop can be
/// driven without a store.
@MainActor
final class FakeCoachChatToolExecutor: CoachChatToolExecutor {
    var results: [String: CoachChatToolResult] = [:]
    /// Answers to `propose_*` in order, so one script can give the drafter and the reviewer
    /// different drafts; falls back to `results` when empty.
    var drafts: [CoachChatToolResult] = []
    var failing: Set<String> = []
    private(set) var calls: [(name: String, arguments: String)] = []

    struct Failure: Error {}

    func execute(name: String, argumentsJSON: String) async throws -> CoachChatToolResult {
        calls.append((name, argumentsJSON))
        if failing.contains(name) { throw Failure() }
        if name.hasPrefix("propose_"), !drafts.isEmpty { return drafts.removeFirst() }
        return results[name] ?? .json(#"{"unknown":true}"#)
    }
}

@MainActor
@Suite("Coach chat engine")
struct CoachChatEngineTests {
    private typealias Fake = FakeOpenRouterTransport

    nonisolated private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let tools: [OpenRouterWire.ToolDefinition] = (try? OpenRouterWire.toolDefinitions()) ?? []

    /// Second opinion off: these tests cover the drafter's loop alone.
    private func engine(
        _ transport: Fake, executor: FakeCoachChatToolExecutor = FakeCoachChatToolExecutor(),
        thread: CoachChatThread? = nil, archive: CoachChatArchive? = nil
    ) -> CoachChatEngine {
        CoachChatEngine(
            client: OpenRouterClient(apiKey: { "or-test" }, transport: transport),
            executor: executor,
            configuration: CoachChatConfiguration(reviewerModelID: nil, consentGiven: true),
            systemPrompt: "You are a coach.", tools: Self.tools, thread: thread, archive: archive,
            clock: { Self.now }
        )
    }

    private static func textReply(_ parts: [String], prompt: Int = 50, completion: Int = 5) -> Fake.Reply {
        Fake.Reply(lines: Fake.sse(
            parts.map(Fake.text) + [Fake.finish("stop"), Fake.usage(prompt: prompt, completion: completion)]
        ))
    }

    private static func toolReply(_ calls: [(id: String, name: String, arguments: String)]) -> Fake.Reply {
        var chunks: [String] = []
        for (index, call) in calls.enumerated() {
            chunks.append(Fake.toolDelta(index: index, id: call.id, name: call.name, arguments: ""))
            chunks.append(Fake.toolDelta(index: index, arguments: call.arguments))
        }
        chunks.append(Fake.finish("tool_calls"))
        chunks.append(Fake.usage(prompt: 100, completion: 10))
        return Fake.Reply(lines: Fake.sse(chunks))
    }

    @Test("a plain answer streams into one assistant bubble and the system prompt leads the wire")
    func plainAnswer() async throws {
        let transport = Fake([Self.textReply(["Bench ", "more."])])
        let engine = engine(transport)
        await engine.send("  How do I bench more?  ")
        #expect(engine.messages.map(\.role) == [.user, .assistant])
        #expect(engine.messages.last?.text == "Bench more.")
        #expect(engine.messages.first?.text == "How do I bench more?")
        #expect(engine.isStreaming == false)
        #expect(engine.lastError == nil)
        #expect(engine.usage.promptTokens == 50)
        #expect(engine.usage.completionTokens == 5)
        #expect(engine.usage.byModel == [
            CoachChatConfiguration.defaultModelID: CoachChatModelUsage(promptTokens: 50, completionTokens: 5)
        ])
        let request = try #require(transport.chatRequest(at: 0))
        #expect(request.messages.first == .system("You are a coach."))
        #expect(request.messages.last == .user("How do I bench more?"))
        #expect(request.tools?.count == CoachChatToolCatalog.tools.count)
        #expect(request.model == CoachChatConfiguration.defaultModelID)
    }

    @Test("tool calls run in order, their results go back as tool messages, then the text lands")
    func toolRound() async throws {
        let executor = FakeCoachChatToolExecutor()
        executor.results["get_profile"] = .json(#"{"unit":"kg"}"#)
        executor.results["get_recovery"] = .json(#"{"chest":0.8}"#)
        let transport = Fake([
            Self.toolReply([("call_1", "get_profile", "{}"), ("call_2", "get_recovery", #"{\"weeks\":2}"#)]),
            Self.textReply(["Rest a day."])
        ])
        let engine = engine(transport, executor: executor)
        await engine.send("Should I train chest today?")

        #expect(executor.calls.map(\.name) == ["get_profile", "get_recovery"])
        #expect(executor.calls.last?.arguments == #"{"weeks":2}"#)
        #expect(engine.messages.map(\.role) == [.user, .tool, .tool, .assistant])
        #expect(engine.messages[1].text == CoachChatToolName.getProfile.activityLabel)
        #expect(engine.messages.last?.text == "Rest a day.")
        #expect(engine.usage.promptTokens == 150)
        #expect(engine.usage.completionTokens == 15)

        let second = try #require(transport.chatRequest(at: 1))
        let assistant = try #require(second.messages.dropLast(2).last)
        #expect(assistant.role == .assistant)
        #expect(assistant.toolCalls?.map(\.id) == ["call_1", "call_2"])
        #expect(assistant.toolCalls?.last?.function.arguments == #"{"weeks":2}"#)
        #expect(Array(second.messages.suffix(2)) == [
            .tool(callID: "call_1", content: #"{"unit":"kg"}"#),
            .tool(callID: "call_2", content: #"{"chest":0.8}"#)
        ])
    }

    @Test("a failing tool goes back to the model as an error result, never to lastError")
    func toolFailure() async throws {
        let executor = FakeCoachChatToolExecutor()
        executor.failing = ["get_workout"]
        let transport = Fake([
            Self.toolReply([("call_1", "get_workout", #"{\"id\":\"nope\"}"#)]),
            Self.textReply(["Couldn't find it."])
        ])
        let engine = engine(transport, executor: executor)
        await engine.send("Show my last workout")
        #expect(engine.lastError == nil)
        #expect(engine.messages[1].isToolError)
        let second = try #require(transport.chatRequest(at: 1))
        let toolMessage = try #require(second.messages.last { $0.role == .tool })
        #expect(toolMessage.content?.hasPrefix(#"{"error":"#) == true)
    }

    @Test("a proposal becomes a draft, a card message, and a compact result for the model")
    func draftResult() async throws {
        let executor = FakeCoachChatToolExecutor()
        let proposal = RoutineProposal(
            name: "Push", exercises: [CoachChatExerciseSpec(exerciseName: "Bench Press", sets: [
                CoachChatSetSpec(targetReps: 5), CoachChatSetSpec(targetReps: 5)
            ])]
        )
        executor.results["propose_routine"] = .draft(.routine(proposal), summaryJSON: #"{"ok":true}"#)
        let transport = Fake([
            Self.toolReply([("call_1", "propose_routine", "{}")]), Self.textReply(["Here's Push."])
        ])
        let engine = engine(transport, executor: executor)
        await engine.send("Build me a push day")
        #expect(engine.drafts == [.routine(proposal)])
        #expect(engine.draftOrigins == [.drafter])
        #expect(engine.reviews.isEmpty)
        #expect(engine.messages.map(\.role) == [.user, .tool, .draft, .assistant])
        #expect(engine.messages[2].draftIndex == 0)
        #expect(engine.messages[2].text == proposal.summary)
        let second = try #require(transport.chatRequest(at: 1))
        #expect(second.messages.last == .tool(callID: "call_1", content: #"{"ok":true}"#))
    }

    @Test("a transport error lands in lastError and the wire rolls back to the user message")
    func transportError() async throws {
        let transport = Fake([
            Fake.Reply(status: 401, lines: [#"{"error":{"code":401,"message":"bad key"}}"#]),
            Self.textReply(["Second try."])
        ])
        let engine = engine(transport)
        await engine.send("Hello")
        #expect(engine.lastError?.kind == .unauthorized)
        // The failure is written into the transcript as a note — and a note is never replayed.
        #expect(engine.messages.map(\.role) == [.user, .assistant])
        #expect(engine.messages.last?.isNote == true)
        await engine.send("Again")
        #expect(engine.lastError == nil)
        let second = try #require(transport.chatRequest(at: 1))
        #expect(second.messages.map(\.role) == [.system, .user, .user])
    }

    @Test("cancelling mid-stream keeps the partial text with a stopped marker")
    func cancelMidStream() async throws {
        var reply = Fake.Reply(lines: Fake.sse([Fake.text("Partial ")], done: false))
        reply.hangs = true
        let transport = Fake([reply, Self.textReply(["Later."])])
        let engine = engine(transport)
        let sending = Task { await engine.send("Talk to me") }
        while engine.messages.count < 2 { await Task.yield() }
        engine.cancel()
        await sending.value
        #expect(engine.isStreaming == false)
        #expect(engine.lastError == nil)
        let last = try #require(engine.messages.last)
        #expect(last.role == .assistant)
        #expect(last.text == "Partial ")
        #expect(last.isStopped)

        await engine.send("Go on")
        let second = try #require(transport.chatRequest(at: 1))
        #expect(second.messages.map(\.role) == [.system, .user, .assistant, .user])
    }

    @Test("after the tool-round cap the model is forced to answer in text")
    func roundCap() async throws {
        let executor = FakeCoachChatToolExecutor()
        var replies = (0..<CoachChatEngine.maxToolRounds).map { _ in
            Self.toolReply([("call", "get_profile", "{}")])
        }
        replies.append(Self.textReply(["Enough."]))
        let transport = Fake(replies)
        let engine = engine(transport, executor: executor)
        await engine.send("Loop forever")
        #expect(executor.calls.count == CoachChatEngine.maxToolRounds)
        #expect(engine.messages.last?.text == "Enough.")
        let requests = transport.requests.withLock { $0.count }
        #expect(requests == CoachChatEngine.maxToolRounds + 1)
        let last = try #require(transport.chatRequest(at: CoachChatEngine.maxToolRounds))
        #expect(last.toolChoice == "none")
        let first = try #require(transport.chatRequest(at: 0))
        #expect(first.toolChoice == nil)
    }

    @Test("a restored thread replays its text and the archive receives every turn")
    func restoreAndArchive() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = CoachChatArchive(directory: directory)
        var thread = CoachChatThread(id: UUID(), createdAt: Self.now, updatedAt: Self.now)
        thread.messages = [
            .user("Earlier question", at: Self.now), .tool("get_profile", at: Self.now),
            .assistant("Earlier answer", at: Self.now)
        ]
        let transport = Fake([Self.textReply(["New answer."])])
        let engine = engine(transport, thread: thread, archive: archive)
        await engine.send("Follow-up")
        let request = try #require(transport.chatRequest(at: 0))
        #expect(request.messages.map(\.role) == [.system, .user, .assistant, .user])
        let saved = try #require(archive.load(id: thread.id))
        #expect(saved.messages.count == 5)
        #expect(saved.messages.last?.text == "New answer.")
        #expect(saved.title == "Earlier question")
        #expect(engine.snapshot() == saved)
    }

    @Test("blank input is ignored")
    func guards() async {
        let transport = Fake([Self.textReply(["A"])])
        let engine = engine(transport)
        await engine.send("   ")
        #expect(engine.messages.isEmpty)
        #expect(transport.requests.withLock { $0.isEmpty })
    }
}
