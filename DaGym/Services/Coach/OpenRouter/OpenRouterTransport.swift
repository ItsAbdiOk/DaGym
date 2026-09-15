import Foundation

/// What `OpenRouterClient` can go wrong with, typed so the chat screen can pick its copy
/// (bad key → Settings link, no credits → openrouter.ai link, rate-limited → retry) instead of
/// showing the server's sentence.
enum OpenRouterError: Error, Sendable {
    /// No key in the Keychain; nothing was sent.
    case missingKey
    /// 401 — the key was rejected.
    case unauthorized
    /// 429 — `retryAfter` in seconds when the server said.
    case rateLimited(retryAfter: TimeInterval?)
    /// 402 — the OpenRouter account has no credit left.
    case insufficientCredits
    /// Any other 4xx, with the server's message.
    case badRequest(String)
    /// 5xx from OpenRouter or the upstream provider.
    case server(Int)
    /// URLSession failed before a response arrived.
    case network(any Error)
    /// The body wasn't the JSON we expected.
    case decoding

    /// Same case, ignoring payloads — for tests and for "is this the same failure again".
    var kind: Kind {
        switch self {
        case .missingKey: .missingKey
        case .unauthorized: .unauthorized
        case .rateLimited: .rateLimited
        case .insufficientCredits: .insufficientCredits
        case .badRequest: .badRequest
        case .server: .server
        case .network: .network
        case .decoding: .decoding
        }
    }

    enum Kind: Equatable, Sendable {
        case missingKey, unauthorized, rateLimited, insufficientCredits, badRequest, server, network, decoding
    }

    /// The provider's own words for a rejected request; empty for the other cases.
    var detail: String {
        if case .badRequest(let message) = self { return message }
        return ""
    }

    /// One line for os.Logger — the key is never part of any case, so nothing here is secret.
    var logDescription: String {
        switch self {
        case .missingKey: "missing key"
        case .unauthorized: "unauthorized"
        case .rateLimited(let retryAfter): "rate limited (retry after \(retryAfter ?? 0)s)"
        case .insufficientCredits: "insufficient credits"
        case .badRequest(let message): "bad request: \(message)"
        case .server(let status): "server error \(status)"
        case .network(let error): "network: \(error.localizedDescription)"
        case .decoding: "undecodable response"
        }
    }

    /// Maps a non-2xx reply (status + decoded error message, if any) to a case.
    static func from(status: Int, message: String?, retryAfter: TimeInterval?) -> OpenRouterError {
        switch status {
        case 401: .unauthorized
        case 402: .insufficientCredits
        case 429: .rateLimited(retryAfter: retryAfter)
        case 500...: .server(status)
        default: .badRequest(message ?? "OpenRouter returned \(status).")
        }
    }
}

/// The response as the client wants it: headers up front, then the body as it arrives, one
/// line at a time (SSE is line-framed; a JSON body is just joined back together).
struct OpenRouterTransportReply: Sendable {
    var response: HTTPURLResponse
    var lines: AsyncThrowingStream<String, any Error>

    /// Reads the whole body — for JSON replies and error envelopes.
    func body() async throws -> Data {
        var collected: [String] = []
        for try await line in lines { collected.append(line) }
        return Data(collected.joined(separator: "\n").utf8)
    }
}

/// The seam between the client and the network. `URLSessionTransport` is the real one; tests
/// hand in a fake that replays recorded SSE.
protocol OpenRouterTransport: Sendable {
    func lines(for request: URLRequest) async throws -> OpenRouterTransportReply
}

struct URLSessionTransport: OpenRouterTransport {
    var session: URLSession = .shared

    func lines(for request: URLRequest) async throws -> OpenRouterTransportReply {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw OpenRouterError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.network(URLError(.badServerResponse))
        }
        let lines = AsyncThrowingStream<String, any Error> { continuation in
            let reader = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: OpenRouterError.network(error))
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
        return OpenRouterTransportReply(response: http, lines: lines)
    }
}
