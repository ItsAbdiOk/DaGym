import Foundation
import Testing

@testable import DaGym

@Suite("OpenRouter client")
struct OpenRouterClientTests {
    private typealias Fake = FakeOpenRouterTransport

    private func client(_ transport: Fake, key: String? = "or-test-key") -> OpenRouterClient {
        OpenRouterClient(apiKey: { key }, transport: transport)
    }

    private func collect(_ client: OpenRouterClient) async throws -> [OpenRouterWire.StreamEvent] {
        var events: [OpenRouterWire.StreamEvent] = []
        let request = OpenRouterWire.ChatRequest(model: "m", messages: [.user("hi")])
        for try await event in client.stream(request: request) { events.append(event) }
        return events
    }

    @Test("SSE text chunks become text events and the usage chunk ends the stream once")
    func streamsText() async throws {
        let transport = Fake([Fake.Reply(lines: Fake.sse([
            Fake.text("Hel"), Fake.text("lo"), Fake.finish("stop"),
            Fake.usage(prompt: 10, completion: 2, cost: 0.001)
        ]))])
        let events = try await collect(client(transport))
        #expect(events == [
            .text("Hel"), .text("lo"),
            .finished(reason: "stop", usage: .init(promptTokens: 10, completionTokens: 2, cost: 0.001))
        ])
    }

    @Test("tool-call fragments are forwarded in order with their index, id and name")
    func streamsToolCalls() async throws {
        let transport = Fake([Fake.Reply(lines: Fake.sse([
            Fake.toolDelta(index: 0, id: "call_1", name: "get_profile", arguments: ""),
            Fake.toolDelta(index: 0, arguments: "{}"),
            Fake.toolDelta(index: 1, id: "call_2", name: "get_recovery", arguments: #"{\"weeks\""#),
            Fake.toolDelta(index: 1, arguments: ":4}"),
            Fake.finish("tool_calls")
        ]))])
        let events = try await collect(client(transport))
        #expect(events == [
            .toolCallDelta(index: 0, id: "call_1", name: "get_profile", argumentsChunk: ""),
            .toolCallDelta(index: 0, id: nil, name: nil, argumentsChunk: "{}"),
            .toolCallDelta(index: 1, id: "call_2", name: "get_recovery", argumentsChunk: #"{"weeks""#),
            .toolCallDelta(index: 1, id: nil, name: nil, argumentsChunk: ":4}"),
            .finished(reason: "tool_calls", usage: nil)
        ])
    }

    @Test("the request carries the bearer key, attribution headers and a streaming body")
    func requestShape() async throws {
        let transport = Fake([Fake.Reply(lines: Fake.sse([Fake.text("ok")]))])
        _ = try await collect(client(transport))
        let request = try #require(transport.requests.withLock { $0.first })
        #expect(request.httpMethod == "POST")
        #expect(request.url == OpenRouterClient.chatURL)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer or-test-key")
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://github.com/ItsAbdiOk/DaGym")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "DaGym")
        let body = try #require(transport.chatRequest(at: 0))
        #expect(body.stream)
        #expect(body.streamOptions?.includeUsage == true)
        #expect(body.messages == [.user("hi")])
    }

    @Test("no key means nothing is sent")
    func missingKey() async {
        let transport = Fake([Fake.Reply(lines: Fake.sse([Fake.text("never")]))])
        await #expect(throws: OpenRouterError.self) { try await collect(client(transport, key: "  ")) }
        #expect(transport.requests.withLock { $0.isEmpty })
    }

    struct HTTPFailure: Sendable {
        var status: Int
        var message: String
        var retryAfter: String?
        var kind: OpenRouterError.Kind
    }

    @Test("HTTP failures map to typed errors, reading the envelope message and Retry-After",
          arguments: [
              HTTPFailure(status: 401, message: "Invalid key", kind: .unauthorized),
              HTTPFailure(status: 402, message: "Insufficient credits", kind: .insufficientCredits),
              HTTPFailure(status: 429, message: "Rate limited", retryAfter: "30", kind: .rateLimited),
              HTTPFailure(status: 400, message: "Bad model", kind: .badRequest),
              HTTPFailure(status: 502, message: "Upstream", kind: .server)
          ])
    func httpErrors(_ failure: HTTPFailure) async {
        let (status, message, kind) = (failure.status, failure.message, failure.kind)
        var reply = Fake.Reply(
            status: status, lines: [#"{"error":{"code":\#(status),"message":"\#(message)"}}"#]
        )
        if let retryAfter = failure.retryAfter { reply.headers["Retry-After"] = retryAfter }
        let transport = Fake([reply])
        do {
            _ = try await collect(client(transport))
            Issue.record("expected a throw")
        } catch let error as OpenRouterError {
            #expect(error.kind == kind)
            if case .badRequest(let text) = error { #expect(text == message) }
            if case .rateLimited(let seconds) = error { #expect(seconds == 30) }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("an error envelope mid-stream throws after the text that already arrived")
    func midStreamError() async {
        let transport = Fake([Fake.Reply(lines: Fake.sse([
            Fake.text("Part"), #"{"error":{"code":429,"message":"Provider overloaded"}}"#
        ], done: false))])
        var events: [OpenRouterWire.StreamEvent] = []
        do {
            let request = OpenRouterWire.ChatRequest(model: "m", messages: [.user("hi")])
            for try await event in client(transport).stream(request: request) { events.append(event) }
            Issue.record("expected a throw")
        } catch let error as OpenRouterError {
            #expect(error.kind == .rateLimited)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
        #expect(events == [.text("Part")])
    }

    @Test("a stream that ends without usage still finishes exactly once; junk lines are skipped")
    func finishesWithoutUsage() async throws {
        let transport = Fake([Fake.Reply(lines: [
            "event: message", "data: " + Fake.text("A"), "", "data: not json at all"
        ])])
        await #expect(throws: OpenRouterError.self) { _ = try await collect(client(transport)) }
        let clean = Fake([Fake.Reply(lines: ["data: " + Fake.text("A"), "data: [DONE]"])])
        let events = try await collect(client(clean))
        #expect(events == [.text("A"), .finished(reason: nil, usage: nil)])
    }

    @Test("a transport failure surfaces as .network")
    func networkFailure() async {
        let transport = Fake([Fake.Reply(failsToConnect: true)])
        do {
            _ = try await collect(client(transport))
            Issue.record("expected a throw")
        } catch let error as OpenRouterError {
            #expect(error.kind == .network)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("the models list is a GET that works without a key and decodes the rows")
    func modelsList() async throws {
        // Two body lines: `body()` must join them back into one JSON document.
        let transport = Fake([Fake.Reply(lines: [
            #"{"data":[{"id":"anthropic/claude-sonnet-5","name":"Sonnet 5","#,
            #""pricing":{"prompt":"0.000002","completion":"0.00001"}}]}"#
        ])])
        let models = try await client(transport, key: nil).models()
        #expect(models.map(\.id) == ["anthropic/claude-sonnet-5"])
        let request = try #require(transport.requests.withLock { $0.first })
        #expect(request.httpMethod == "GET")
        #expect(request.url == OpenRouterClient.modelsURL)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("payload parsing strips the data prefix and ignores comments and blanks")
    func payloadParsing() {
        #expect(OpenRouterClient.payload(of: "data: {\"a\":1}") == "{\"a\":1}")
        #expect(OpenRouterClient.payload(of: "data:[DONE]") == "[DONE]")
        #expect(OpenRouterClient.payload(of: ": OPENROUTER PROCESSING") == nil)
        #expect(OpenRouterClient.payload(of: "") == nil)
        #expect(OpenRouterClient.payload(of: "event: ping") == nil)
    }
}
