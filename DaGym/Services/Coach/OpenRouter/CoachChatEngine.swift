import Foundation
import GymCore
import os

/// One chat thread with the cloud coach: the transcript the screen renders, the wire transcript
/// the model sees, and the agent loop between them — stream a reply, run every tool it asked
/// for, send the results back, repeat (at most `maxToolRounds` times), then show the answer.
/// Tool failures go back to the model as `{"error": …}`; only transport failures reach
/// `lastError`. Cancelling leaves what was streamed plus a "stopped" marker.
///
/// When a second-opinion model is configured, every new proposal the drafter makes is then
/// sent to it (`CoachChatEngine+Review.swift`): it agrees or puts up its own draft, and the
/// lifter picks between the cards.
@MainActor
@Observable
final class CoachChatEngine {
    /// Twelve, not eight: a routine for a lifter with no history is four or five muscle-group
    /// searches plus the reads, and the eval showed the drafter still searching when the cap
    /// forced it to answer with nothing. Rounds are cheap next to a bad answer.
    static let maxToolRounds = 12
    /// One silent retry when a reply comes back completely empty — a provider hiccup more often
    /// than a real failure, and cheaper for the lifter than a "try again" note.
    static let emptyReplyRetries = 1

    static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "coachChat")

    let threadID: UUID
    private(set) var messages: [CoachChatMessage]
    private(set) var drafts: [CoachChatDraft]
    /// Parallel to `drafts`: who wrote each one.
    private(set) var draftOrigins: [CoachChatDraftOrigin]
    /// One per reviewed draft, in the order the reviews finished.
    private(set) var reviews: [CoachChatReview]
    private(set) var isStreaming = false
    private(set) var lastError: OpenRouterError?
    private(set) var usage: CoachChatUsage
    private(set) var kind: CoachChatThreadKind
    private(set) var weekReviewKey: String?

    let client: OpenRouterClient
    let executor: any CoachChatToolExecutor
    let configuration: CoachChatConfiguration
    let systemPrompt: String
    let tools: [OpenRouterWire.ToolDefinition]
    /// The reviewer's catalogue: the drafter's tools plus `agree_with_proposal`.
    let reviewerTools: [OpenRouterWire.ToolDefinition]
    let clock: @Sendable () -> Date
    private let archive: CoachChatArchive?
    /// The cross-thread counters for Settings › Coach usage; nil in tests that do not care.
    private let ledger: CoachChatUsageLedgerStore?
    private let createdAt: Date
    /// What the model sees: system prompt is prepended per request; tool calls and results stay
    /// so later turns can build on earlier lookups. Rebuilt from text only on restore.
    private var wire: [OpenRouterWire.Message] = []
    private var turn: Task<Void, Never>?

    /// `systemPrompt` is `CoachChatPrompt.system(...)` and `tools` is
    /// `OpenRouterWire.toolDefinitions()` — both built by the caller so a test can hand in a
    /// one-tool catalogue and a fixed prompt. `reviewerTools` defaults to the full reviewer
    /// catalogue; the reviewer only runs when `configuration.reviewerModelID` is set.
    init(
        client: OpenRouterClient,
        executor: any CoachChatToolExecutor,
        configuration: CoachChatConfiguration,
        systemPrompt: String,
        tools: [OpenRouterWire.ToolDefinition],
        reviewerTools: [OpenRouterWire.ToolDefinition]? = nil,
        thread: CoachChatThread? = nil,
        archive: CoachChatArchive? = nil,
        ledger: CoachChatUsageLedgerStore? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.executor = executor
        self.configuration = configuration
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.reviewerTools = reviewerTools
            ?? (try? OpenRouterWire.toolDefinitions(CoachChatToolCatalog.reviewerTools)) ?? []
        self.archive = archive
        self.ledger = ledger
        self.clock = clock
        threadID = thread?.id ?? UUID()
        createdAt = thread?.createdAt ?? clock()
        messages = thread?.messages ?? []
        let restoredDrafts = thread?.drafts ?? []
        drafts = restoredDrafts
        let origins = thread?.draftOrigins ?? []
        draftOrigins = restoredDrafts.indices.map { origins.indices.contains($0) ? origins[$0] : .drafter }
        reviews = thread?.reviews ?? []
        usage = thread?.usage ?? CoachChatUsage()
        kind = thread?.kind ?? .chat
        weekReviewKey = thread?.weekReviewKey
        wire = Self.wireTranscript(from: messages)
    }

    /// The thread as the archive stores it.
    func snapshot() -> CoachChatThread {
        CoachChatThread(
            id: threadID, createdAt: createdAt, updatedAt: messages.last?.sentAt ?? createdAt,
            messages: messages, drafts: drafts, draftOrigins: draftOrigins, reviews: reviews, usage: usage,
            kind: kind, weekReviewKey: weekReviewKey
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
        let draftBase = drafts.count
        let task = Task {
            let finished = await runTurn()
            guard finished, configuration.reviewerModelID != nil else { return }
            await reviewNewDrafts(from: draftBase, request: trimmed)
        }
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

    /// True when the turn reached its final text; false when it failed or was stopped, in
    /// which case nothing the drafter proposed goes for review.
    private func runTurn() async -> Bool {
        let wireBase = wire.count
        var round = 0
        var emptyRetries = 0
        while round <= Self.maxToolRounds {
            defer { round += 1 }
            // Past the round cap the model must answer in words.
            let forceText = round == Self.maxToolRounds
            let request = OpenRouterWire.ChatRequest(
                model: configuration.modelID, messages: [.system(systemPrompt)] + wire,
                tools: tools.isEmpty ? nil : tools, toolChoice: forceText ? "none" : nil,
                maxTokens: configuration.maxTokens
            )
            Self.trace("round \(round): \(request.messages.count) messages, tools \(tools.count)"
                + (forceText ? ", text forced" : ""))
            let reply: Reply
            do {
                reply = try await consume(request)
                Self.trace("reply: \(reply.text.count) chars, \(reply.calls.count) tool calls "
                    + reply.calls.map { "\($0.function.name)(\($0.function.arguments.count)b)" }
                        .joined(separator: " "))
            } catch is CancellationError {
                abandonTurn(from: wireBase, stopped: true)
                return false
            } catch let error as OpenRouterError {
                fail(error, from: wireBase)
                return false
            } catch {
                fail(.network(error), from: wireBase)
                return false
            }
            if reply.text.isEmpty, reply.calls.isEmpty {
                // Nothing came back at all. Retry once (provider hiccup), then say so in the
                // transcript rather than end the turn in silence.
                if emptyRetries < Self.emptyReplyRetries {
                    emptyRetries += 1
                    round -= 1
                    Self.trace("empty reply, retrying once")
                    continue
                }
                noteEmptyReply(reply, from: wireBase)
                return false
            }
            wire.append(.assistant(
                reply.text.isEmpty ? nil : reply.text, toolCalls: reply.calls.isEmpty ? nil : reply.calls
            ))
            if reply.calls.isEmpty { return true }
            for call in reply.calls {
                if Task.isCancelled {
                    abandonTurn(from: wireBase, stopped: true)
                    return false
                }
                let content = await execute(call, origin: .drafter, reviewIndex: nil, chipPrefix: nil)
                wire.append(.tool(callID: call.id, content: content))
            }
        }
        noteRoundCap(from: wireBase)
        return false
    }

    /// The streamed part of one model reply, with tool-call fragments already concatenated.
    struct Reply {
        var text = ""
        var calls: [OpenRouterWire.ToolCall] = []
        var finishReason: String?
    }

    /// Streams one reply into the transcript. The drafter's text lands in an assistant bubble;
    /// a `reviewIndex` puts it in a `.review` row instead. Usage is booked to the request's model.
    func consume(_ request: OpenRouterWire.ChatRequest, reviewIndex: Int? = nil) async throws -> Reply {
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
                    if let reviewIndex {
                        messages.append(.review(reply.text, index: reviewIndex, at: clock()))
                    } else {
                        messages.append(.assistant(reply.text, at: clock()))
                    }
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
                if let turnUsage {
                    usage.add(turnUsage, model: request.model)
                    ledger?.record(turnUsage, model: request.model, at: clock())
                }
                reply.finishReason = reason
                if reason == "length", let bubbleIndex { messages[bubbleIndex].isStopped = true }
            }
        }
        // A cancelled consumer sees the stream end rather than throw; make it throw here so the
        // turn is abandoned instead of a half-reply being sent back as if it were whole.
        try Task.checkCancellation()
        reply.calls = Self.orderedCalls(calls)
        return reply
    }

    /// Runs one tool call, showing an activity chip while it runs, and returns what the model
    /// gets back: the tool's JSON, the draft's compact summary, or `{"error": …}`. The
    /// reviewer's calls carry its short name on the chip ("Opus · Reading exercise history").
    func execute(
        _ call: OpenRouterWire.ToolCall, origin: CoachChatDraftOrigin, reviewIndex: Int?, chipPrefix: String?
    ) async -> String {
        let chipIndex = messages.count
        var chip = CoachChatMessage.tool(call.function.name, at: clock())
        if let subject = Self.chipSubject(from: call.function.arguments) { chip.text += " · \(subject)" }
        if let chipPrefix { chip.text = "\(chipPrefix) · \(chip.text)" }
        chip.reviewIndex = reviewIndex
        messages.append(chip)
        do {
            let result = try await executor.execute(
                name: call.function.name, argumentsJSON: call.function.arguments
            )
            switch result {
            case .json(let json):
                return json
            case .draft(let draft, let summaryJSON):
                appendDraft(draft, origin: origin, reviewIndex: reviewIndex)
                return summaryJSON
            }
        } catch {
            messages[chipIndex].isToolError = true
            let name = call.function.name
            let reason = error.localizedDescription
            Self.logger.notice("Tool \(name, privacy: .public) failed: \(reason, privacy: .public)")
            Self.trace("failed arguments head: \(call.function.arguments.prefix(300))")
            return Self.errorJSON(error.localizedDescription)
        }
    }

    /// Rolls the wire transcript back to the user message so no assistant tool call is left
    /// without its result (the API rejects that), keeping any text that did stream as context.
    func abandonTurn(from wireBase: Int, stopped: Bool) {
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
            case .assistant: message.text.isEmpty || message.isNote == true ? nil : .assistant(message.text)
            case .tool, .draft, .review: nil
            }
        }
    }
}

// MARK: - Week review

extension CoachChatEngine {
    /// Turns a fresh thread into the Sunday check-in and sends the canned turn
    /// (`CoachWeekReviewPrompt.userTurn`), which runs through the ordinary loop — tools,
    /// proposals, second opinion. The thread is filed at once so Home sees it as started even
    /// if the reply never lands. A thread that already has messages is left alone.
    func startWeekReview(weekEnding: Date, calendar: Calendar) async {
        guard messages.isEmpty, !isStreaming else { return }
        kind = .weekReview
        weekReviewKey = DateKey.string(for: weekEnding, calendar: calendar)
        persist()
        await send(CoachWeekReviewPrompt.userTurn(weekEnding: weekEnding, calendar: calendar))
    }
}

// MARK: - Drafts and reviews (what the cards read)

extension CoachChatEngine {
    /// Who wrote `drafts[index]`.
    func origin(ofDraft index: Int) -> CoachChatDraftOrigin {
        draftOrigins.indices.contains(index) ? draftOrigins[index] : .drafter
    }

    /// The review of a drafter's draft, or the review that produced a reviewer's draft.
    func review(forDraft index: Int) -> CoachChatReview? {
        reviews.first { $0.draftIndex == index || $0.alternativeDraftIndex == index }
    }

    /// The other card in a pair: the reviewer's alternative for a drafter's draft, and the
    /// drafter's original for the alternative. Applying one discards the other.
    func linkedDraftIndex(for index: Int) -> Int? {
        guard let review = review(forDraft: index), let alternative = review.alternativeDraftIndex else {
            return nil
        }
        return alternative == index ? review.draftIndex : alternative
    }

    /// Appends a draft from either model and its card row; returns its index.
    @discardableResult
    func appendDraft(_ draft: CoachChatDraft, origin: CoachChatDraftOrigin, reviewIndex: Int?) -> Int {
        drafts.append(draft)
        draftOrigins.append(origin)
        let index = drafts.count - 1
        var card = CoachChatMessage.draft(index: index, summary: draft.summary, at: clock())
        card.reviewIndex = reviewIndex
        messages.append(card)
        return index
    }

    func appendMessage(_ message: CoachChatMessage) {
        messages.append(message)
    }

    func markToolError(at index: Int) {
        messages[index].isToolError = true
    }

    func recordReview(_ review: CoachChatReview) {
        reviews.append(review)
    }
}

// MARK: - Turn endings

extension CoachChatEngine {
    /// A failed round: the banner gets the typed error, and the transcript gets a line saying so
    /// in place — a turn that ends in nothing after a row of tool chips reads as "it broke", and
    /// the banner alone was easy to scroll past.
    func fail(_ error: OpenRouterError, from wireBase: Int) {
        lastError = error
        Self.logger.error("Coach turn failed: \(error.logDescription, privacy: .public)")
        abandonTurn(from: wireBase, stopped: false)
        messages.append(.note(Self.failureLine(for: error), at: clock()))
    }

    /// Nothing came back at all, even after the retry — usually the generation cap swallowed
    /// by reasoning, or a provider hiccup.
    func noteEmptyReply(_ reply: Reply, from wireBase: Int) {
        let why = reply.finishReason == "length"
            ? "The model ran out of room before answering (it spent its budget thinking). Try again."
            : "The model returned an empty reply. Try again."
        Self.trace("empty reply, finish \(reply.finishReason ?? "nil")")
        abandonTurn(from: wireBase, stopped: false)
        messages.append(.note(why, at: clock()))
    }

    /// The model kept calling tools through the forced-text round: nothing to show, so say so.
    func noteRoundCap(from wireBase: Int) {
        Self.trace("round cap reached without a text reply")
        abandonTurn(from: wireBase, stopped: false)
        messages.append(.note(
            "The coach ran out of steps before answering (it kept reading data). Ask again, "
                + "or narrow the question.", at: clock()
        ))
    }
}
