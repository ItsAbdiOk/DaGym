import Foundation
import os

/// Talks to OpenRouter's OpenAI-compatible API with the lifter's own key (BYOK). The key is
/// read through a closure at request time so it is never held here, and it is only ever put in
/// the `Authorization` header — never logged. Streaming responses come back as `StreamEvent`s
/// with the SSE framing already stripped; the models list is a plain GET.
actor OpenRouterClient {
    static let chatURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")
    static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")
    /// OpenRouter's attribution headers; they show the app on the key's activity page.
    static let referer = "https://github.com/ItsAbdiOk/DaGym"
    static let title = "DaGym"

    private static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "openrouter")
    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let apiKey: @Sendable () -> String?
    private let transport: any OpenRouterTransport

    init(apiKey: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.init(apiKey: apiKey, transport: URLSessionTransport(session: session))
    }

    init(apiKey: @escaping @Sendable () -> String?, transport: any OpenRouterTransport) {
        self.apiKey = apiKey
        self.transport = transport
    }

    // MARK: - Chat

    /// Streams one completion. Finishes with `.finished` (once) or throws an `OpenRouterError`.
    /// Cancelling the consuming task tears the connection down.
    nonisolated func stream(
        request: OpenRouterWire.ChatRequest
    ) -> AsyncThrowingStream<OpenRouterWire.StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: OpenRouterWire.ChatRequest,
        into continuation: AsyncThrowingStream<OpenRouterWire.StreamEvent, any Error>.Continuation
    ) async throws {
        guard let url = Self.chatURL else { throw OpenRouterError.badRequest("Bad request URL.") }
        var urlRequest = try authorisedRequest(url: url, requireKey: true)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            urlRequest.httpBody = try Self.encoder.encode(request)
        } catch {
            throw OpenRouterError.badRequest("Couldn't encode the request.")
        }

        let reply = try await transport.lines(for: urlRequest)
        try await Self.throwIfFailed(reply)

        var finishReason: String?
        var finished = false
        for try await line in reply.lines {
            try Task.checkCancellation()
            guard let payload = Self.payload(of: line) else { continue }
            if payload == "[DONE]" { break }
            let chunk = try Self.decodeChunk(payload)
            if let error = chunk.error {
                throw OpenRouterError.from(status: error.code ?? 400, message: error.message, retryAfter: nil)
            }
            for choice in chunk.choices ?? [] {
                Self.emit(choice, into: continuation)
                if let reason = choice.finishReason { finishReason = reason }
            }
            if let usage = chunk.usage {
                continuation.yield(.finished(reason: finishReason, usage: usage))
                finished = true
            }
        }
        if !finished { continuation.yield(.finished(reason: finishReason, usage: nil)) }
    }

    private static func emit(
        _ choice: OpenRouterWire.StreamChoice,
        into continuation: AsyncThrowingStream<OpenRouterWire.StreamEvent, any Error>.Continuation
    ) {
        guard let delta = choice.delta else { return }
        if let text = delta.content, !text.isEmpty { continuation.yield(.text(text)) }
        for call in delta.toolCalls ?? [] {
            continuation.yield(.toolCallDelta(
                index: call.index, id: call.id, name: call.function?.name,
                argumentsChunk: call.function?.arguments ?? ""
            ))
        }
    }

    /// The `data:` payload of an SSE line; nil for blank lines, comments (`: OPENROUTER PROCESSING`
    /// keep-alives) and other fields.
    static func payload(of line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }

    private static func decodeChunk(_ payload: String) throws -> OpenRouterWire.StreamChunk {
        do {
            return try decoder.decode(OpenRouterWire.StreamChunk.self, from: Data(payload.utf8))
        } catch {
            logger.error("Undecodable stream chunk: \(error.localizedDescription, privacy: .public)")
            throw OpenRouterError.decoding
        }
    }

    // MARK: - Models

    /// The public catalogue. Sends the key when there is one (personalised pricing) but doesn't
    /// need it, so the picker works before the lifter has pasted a key.
    func models() async throws -> [OpenRouterWire.Model] {
        guard let url = Self.modelsURL else { throw OpenRouterError.badRequest("Bad request URL.") }
        var request = try authorisedRequest(url: url, requireKey: false)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let reply = try await transport.lines(for: request)
        try await Self.throwIfFailed(reply)
        let body = try await reply.body()
        do {
            return try Self.decoder.decode(OpenRouterWire.ModelsResponse.self, from: body).data
        } catch {
            Self.logger.error("Undecodable models list: \(error.localizedDescription, privacy: .public)")
            throw OpenRouterError.decoding
        }
    }

    // MARK: - Shared

    private func authorisedRequest(url: URL, requireKey: Bool) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(Self.title, forHTTPHeaderField: "X-Title")
        let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else if requireKey {
            throw OpenRouterError.missingKey
        }
        return request
    }

    /// Turns a non-2xx reply into the matching `OpenRouterError`, reading the envelope for the
    /// message. The status code is logged; the body (which can echo the request) is not.
    private static func throwIfFailed(_ reply: OpenRouterTransportReply) async throws {
        let status = reply.response.statusCode
        guard !(200..<300).contains(status) else { return }
        let body = try? await reply.body()
        let message = body.flatMap { try? decoder.decode(OpenRouterWire.ErrorEnvelope.self, from: $0) }?
            .error.message
        let retryAfter = reply.response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        logger.error("OpenRouter replied \(status, privacy: .public)")
        throw OpenRouterError.from(status: status, message: message, retryAfter: retryAfter)
    }
}
