import Foundation
import GymCore
import Testing

@testable import DaGym

/// The second opinion, driven through the fake transport: the drafter proposes, then the
/// reviewer model gets its own request and agrees, proposes an alternative, fails or is stopped.
@MainActor
@Suite("Coach chat engine: second opinion")
struct CoachChatReviewEngineTests {
    private typealias Fake = FakeOpenRouterTransport

    nonisolated private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let tools: [OpenRouterWire.ToolDefinition] = (try? OpenRouterWire.toolDefinitions()) ?? []
    private static let reviewerTools: [OpenRouterWire.ToolDefinition] =
        (try? OpenRouterWire.toolDefinitions(CoachChatToolCatalog.reviewerTools)) ?? []
    private static let reviewer = CoachChatConfiguration.defaultReviewerModelID
    private static let proposal = RoutineProposal(
        name: "Push", exercises: [CoachChatExerciseSpec(exerciseName: "Bench Press", sets: [
            CoachChatSetSpec(targetReps: 5), CoachChatSetSpec(targetReps: 5)
        ])]
    )
    private static let alternative = RoutineProposal(
        name: "Push", exercises: [CoachChatExerciseSpec(exerciseName: "Bench Press", sets: [
            CoachChatSetSpec(targetReps: 8), CoachChatSetSpec(targetReps: 8), CoachChatSetSpec(targetReps: 8)
        ])]
    )

    private func engine(
        _ transport: Fake, executor: FakeCoachChatToolExecutor, reviewer: String? = reviewer,
        archive: CoachChatArchive? = nil
    ) -> CoachChatEngine {
        CoachChatEngine(
            client: OpenRouterClient(apiKey: { "or-test" }, transport: transport),
            executor: executor,
            configuration: CoachChatConfiguration(reviewerModelID: reviewer, consentGiven: true),
            systemPrompt: "You are a coach.", tools: Self.tools, reviewerTools: Self.reviewerTools,
            archive: archive, clock: { Self.now }
        )
    }

    /// An executor that turns `propose_routine` into the drafter's draft first, then the
    /// reviewer's alternative.
    private func makeExecutor() -> FakeCoachChatToolExecutor {
        let executor = FakeCoachChatToolExecutor()
        executor.drafts = [
            .draft(.routine(Self.proposal), summaryJSON: #"{"ok":true}"#),
            .draft(.routine(Self.alternative), summaryJSON: #"{"ok":true}"#)
        ]
        executor.results["get_exercise_history"] = .json(#"{"best":100}"#)
        return executor
    }

    private static func reply(
        text: [String] = [], calls: [(id: String, name: String, arguments: String)] = [],
        prompt: Int = 100, completion: Int = 10
    ) -> Fake.Reply {
        var chunks = text.map(Fake.text)
        for (index, call) in calls.enumerated() {
            chunks.append(Fake.toolDelta(index: index, id: call.id, name: call.name, arguments: ""))
            chunks.append(Fake.toolDelta(index: index, arguments: call.arguments))
        }
        chunks.append(Fake.finish(calls.isEmpty ? "stop" : "tool_calls"))
        chunks.append(Fake.usage(prompt: prompt, completion: completion))
        return Fake.Reply(lines: Fake.sse(chunks))
    }

    /// The drafter's two replies: a proposal, then its closing words.
    private static var drafterReplies: [Fake.Reply] {
        [
            reply(calls: [("call_1", "propose_routine", "{}")]),
            reply(text: ["Here's Push."], prompt: 50, completion: 5)
        ]
    }

    @Test("the reviewer gets its own request with the addendum and the proposal, and its agreement lands")
    func agrees() async throws {
        let agree = #"{\"reasons\":[\"Volume matches the last 4 weeks\",\"5 reps suits strength\"],"#
            + #"\"confidence\":\"high\"}"#
        let transport = Fake(Self.drafterReplies + [
            Self.reply(calls: [("call_r1", "agree_with_proposal", agree)], prompt: 200, completion: 20)
        ])
        let executor = makeExecutor()
        let engine = engine(transport, executor: executor)
        await engine.send("Build me a push day")

        #expect(transport.requests.withLock { $0.count } == 3)
        let request = try #require(transport.chatRequest(at: 2))
        #expect(request.model == Self.reviewer)
        #expect(request.tools?.count == CoachChatToolCatalog.reviewerTools.count)
        #expect(request.messages.map(\.role) == [.system, .user])
        let system = try #require(request.messages.first?.content)
        #expect(system.hasPrefix("You are a coach."))
        #expect(system.contains("Gemini 3.1 Pro has read the same data"))
        let user = try #require(request.messages.last?.content)
        #expect(user.contains("The lifter asked:\nBuild me a push day"))
        #expect(user.contains("Gemini 3.1 Pro said:\nHere's Push."))
        #expect(user.contains("Proposal (JSON):\n{\"tool\":\"propose_routine\",\"arguments\":{"))
        #expect(user.contains(#""exercise_name":"Bench Press""#))
        // The agree call is the engine's to answer; the executor never sees it.
        #expect(executor.calls.map(\.name) == ["propose_routine"])

        #expect(engine.reviews == [CoachChatReview(
            draftIndex: 0, reviewerModelID: Self.reviewer,
            verdict: .agreed(
                reasons: ["Volume matches the last 4 weeks", "5 reps suits strength"], confidence: "high"
            ),
            finishedAt: Self.now
        )])
        #expect(engine.drafts.count == 1)
        #expect(engine.messages.map(\.role) == [.user, .tool, .draft, .assistant, .tool, .tool, .review])
        #expect(engine.messages[4].text == "Second opinion · Claude Opus 5")
        #expect(engine.messages[4].reviewIndex == 0)
        #expect(engine.messages[5].text == "Opus · Agreeing with the proposal")
        #expect(engine.messages[5].isToolError == false)
        let verdict = try #require(engine.messages.last)
        let agreed = "Claude Opus 5 agrees: Volume matches the last 4 weeks · 5 reps suits strength"
        #expect(verdict.text == agreed)
        #expect(verdict.reviewIndex == 0)
        #expect(verdict.isNote == nil)
        #expect(engine.review(forDraft: 0)?.alternativeDraftIndex == nil)
        #expect(engine.linkedDraftIndex(for: 0) == nil)
        #expect(engine.isStreaming == false)
        #expect(engine.lastError == nil)

        #expect(engine.usage.promptTokens == 350)
        #expect(engine.usage.completionTokens == 35)
        #expect(engine.usage.byModel[CoachChatConfiguration.defaultModelID]?.promptTokens == 150)
        let reviewerUsage = CoachChatModelUsage(promptTokens: 200, completionTokens: 20)
        #expect(engine.usage.byModel[Self.reviewer] == reviewerUsage)
    }

    @Test("a reviewer that reads data and proposes its own version adds a linked reviewer draft")
    func alternative() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = CoachChatArchive(directory: directory)
        let transport = Fake(Self.drafterReplies + [
            Self.reply(calls: [("call_r1", "get_exercise_history", #"{\"exercise_name\":\"Bench Press\"}"#)]),
            Self.reply(text: ["Three sets of eight: ", "the log shows 5s stalling."],
                       calls: [("call_r2", "propose_routine", "{}")])
        ])
        let executor = makeExecutor()
        let engine = engine(transport, executor: executor, archive: archive)
        await engine.send("Build me a push day")

        #expect(executor.calls.map(\.name) == ["propose_routine", "get_exercise_history", "propose_routine"])
        #expect(engine.drafts == [.routine(Self.proposal), .routine(Self.alternative)])
        #expect(engine.draftOrigins == [.drafter, .reviewer])
        #expect(engine.reviews.map(\.verdict) == [
            .alternative(draftIndex: 1, rationale: "Three sets of eight: the log shows 5s stalling.")
        ])
        #expect(engine.messages.map(\.role) == [
            .user, .tool, .draft, .assistant, .tool, .tool, .review, .tool, .draft
        ])
        #expect(engine.messages[5].text == "Opus · Reading exercise history · Bench Press")
        #expect(engine.messages[6].text == "Three sets of eight: the log shows 5s stalling.")
        #expect(engine.messages[7].text == "Opus · Drafting a routine")
        #expect(engine.messages[8].draftIndex == 1)
        #expect(engine.messages[8].reviewIndex == 0)
        #expect(engine.linkedDraftIndex(for: 0) == 1)
        #expect(engine.linkedDraftIndex(for: 1) == 0)
        #expect(engine.review(forDraft: 1)?.draftIndex == 0)
        #expect(engine.origin(ofDraft: 1) == .reviewer)

        // The third reviewer round carries the read's result back, as the drafter's loop does.
        let second = try #require(transport.chatRequest(at: 3))
        #expect(second.messages.last == .tool(callID: "call_r1", content: #"{"best":100}"#))

        let saved = try #require(archive.load(id: engine.threadID))
        #expect(saved.reviews == engine.reviews)
        #expect(saved.draftOrigins == [.drafter, .reviewer])
        #expect(saved.origin(ofDraft: 1) == .reviewer)
        #expect(saved == engine.snapshot())
    }

    @Test("a reviewer transport error is a failed review and a muted note; the drafter's card stands")
    func transportError() async throws {
        let transport = Fake(Self.drafterReplies + [
            Fake.Reply(status: 500, lines: [#"{"error":{"code":500,"message":"upstream"}}"#])
        ])
        let engine = engine(transport, executor: makeExecutor())
        await engine.send("Build me a push day")
        #expect(engine.lastError == nil)
        #expect(engine.drafts.count == 1)
        #expect(engine.reviews.map(\.verdict) == [
            .failed(reason: CoachChatEngine.failureLine(for: .server(500)))
        ])
        let note = try #require(engine.messages.last)
        #expect(note.role == .review)
        #expect(note.isNote == true)
        #expect(note.text.hasPrefix("Claude Opus 5 couldn't review this:"))
        #expect(engine.messages.map(\.role) == [.user, .tool, .draft, .assistant, .tool, .review])
    }

    @Test("with the second opinion off no review request is made")
    func reviewerOff() async throws {
        let transport = Fake(Self.drafterReplies)
        let engine = engine(transport, executor: makeExecutor(), reviewer: nil)
        await engine.send("Build me a push day")
        #expect(transport.requests.withLock { $0.count } == 2)
        #expect(engine.reviews.isEmpty)
        #expect(engine.messages.map(\.role) == [.user, .tool, .draft, .assistant])
    }

    @Test("a turn without a proposal never reaches the reviewer")
    func noDraftNoReview() async throws {
        let transport = Fake([Self.reply(text: ["Rest today."])])
        let engine = engine(transport, executor: makeExecutor())
        await engine.send("Should I train?")
        #expect(transport.requests.withLock { $0.count } == 1)
        #expect(engine.reviews.isEmpty)
    }

    @Test("stopping during the review records it as failed and keeps the drafter's card")
    func cancelDuringReview() async throws {
        var hanging = Fake.Reply(lines: Fake.sse([Fake.text("Checking ")], done: false))
        hanging.hangs = true
        let transport = Fake(Self.drafterReplies + [hanging])
        let engine = engine(transport, executor: makeExecutor())
        let sending = Task { await engine.send("Build me a push day") }
        while !engine.messages.contains(where: { $0.role == .review }) { await Task.yield() }
        engine.cancel()
        await sending.value
        #expect(engine.isStreaming == false)
        #expect(engine.drafts.count == 1)
        #expect(engine.reviews.map(\.verdict) == [.failed(reason: "Stopped before a verdict.")])
        #expect(engine.messages.last?.isNote == true)
        #expect(engine.lastError == nil)
    }

    @Test("a thread archived before the second opinion existed still decodes")
    func legacyThreadDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","createdAt":"2026-09-15T10:00:00Z","updatedAt":"2026-09-15T10:00:00Z",
        "messages":[],"drafts":[],"usage":{"promptTokens":3,"completionTokens":1}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let thread = try decoder.decode(CoachChatThread.self, from: Data(json.utf8))
        #expect(thread.reviews.isEmpty)
        #expect(thread.draftOrigins.isEmpty)
        #expect(thread.usage == CoachChatUsage(promptTokens: 3, completionTokens: 1))
        #expect(thread.origin(ofDraft: 0) == .drafter)
    }
}
