import Foundation
import Synchronization

@testable import DaGym

/// Replays scripted replies to `OpenRouterClient` in order, one per request, and records the
/// requests so tests can check headers and bodies. No network, no key.
final class FakeOpenRouterTransport: OpenRouterTransport, Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var lines: [String] = []
        /// Leave the stream open after `lines` so a test can cancel mid-reply.
        var hangs = false
        var failsToConnect = false
    }

    private let replies: Mutex<[Reply]>
    let requests = Mutex<[URLRequest]>([])

    init(_ replies: [Reply]) {
        self.replies = Mutex(replies)
    }

    /// Frames JSON chunks as an SSE body, keep-alive comment included, ending in `[DONE]`.
    static func sse(_ chunks: [String], done: Bool = true) -> [String] {
        var lines = [": OPENROUTER PROCESSING", ""]
        for chunk in chunks {
            lines.append("data: \(chunk)")
            lines.append("")
        }
        if done { lines.append("data: [DONE]") }
        return lines
    }

    /// A text-only chunk.
    static func text(_ content: String) -> String {
        #"{"id":"gen-1","choices":[{"index":0,"delta":{"role":"assistant","content":"\#(content)"}}]}"#
    }

    /// A tool-call fragment for `index`; `id`/`name` only on the first fragment.
    static func toolDelta(index: Int, id: String? = nil, name: String? = nil, arguments: String) -> String {
        var function = #""arguments":"\#(arguments)""#
        if let name { function = #""name":"\#(name)","# + function }
        var call = #""index":\#(index),"#
        if let id { call += #""id":"\#(id)","type":"function","# }
        return #"{"choices":[{"index":0,"delta":{"tool_calls":[{\#(call)"function":{\#(function)}}]}}]}"#
    }

    static func finish(_ reason: String) -> String {
        #"{"choices":[{"index":0,"delta":{},"finish_reason":"\#(reason)"}]}"#
    }

    static func usage(prompt: Int, completion: Int, cost: Double? = nil) -> String {
        let costField = cost.map { #","cost":\#($0)"# } ?? ""
        let usage = #""prompt_tokens":\#(prompt),"completion_tokens":\#(completion)\#(costField)"#
        return #"{"choices":[],"usage":{\#(usage)}}"#
    }

    func lines(for request: URLRequest) async throws -> OpenRouterTransportReply {
        requests.withLock { $0.append(request) }
        let reply = replies.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        guard let reply, !reply.failsToConnect else {
            throw OpenRouterError.network(URLError(.notConnectedToInternet))
        }
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers
              )
        else { throw OpenRouterError.network(URLError(.badURL)) }
        let stream = AsyncThrowingStream<String, any Error> { continuation in
            for line in reply.lines { continuation.yield(line) }
            if !reply.hangs { continuation.finish() }
        }
        return OpenRouterTransportReply(response: response, lines: stream)
    }

    /// The JSON body of the `index`th request, decoded as a `ChatRequest`.
    func chatRequest(at index: Int) -> OpenRouterWire.ChatRequest? {
        let body = requests.withLock { $0.indices.contains(index) ? $0[index].httpBody : nil }
        return body.flatMap { try? JSONDecoder().decode(OpenRouterWire.ChatRequest.self, from: $0) }
    }
}
