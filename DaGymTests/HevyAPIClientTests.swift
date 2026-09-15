import Foundation
import GymCore
import Synchronization
import Testing

@testable import DaGym

/// Serves canned responses to `HevyAPIClient` through a `URLProtocol`, keyed on the request's
/// `page` query item, so the paging loop runs against a real `URLSession` without a network.
final class HevyStubProtocol: URLProtocol {
    struct Reply: Sendable {
        var status: Int
        var body: String
        var transportError: Bool = false
    }

    /// Page number → reply. A page with no entry falls back to `anyPage`, else a transport failure.
    static let replies = Mutex<[Int: Reply]>([:])
    static let anyPage = Mutex<Reply?>(nil)
    static let seenRequests = Mutex<[URLRequest]>([])

    static func reset(_ pages: [Int: Reply]) {
        replies.withLock { $0 = pages }
        anyPage.withLock { $0 = nil }
        seenRequests.withLock { $0 = [] }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seenRequests.withLock { $0.append(request) }
        let page = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 0
        let reply = Self.replies.withLock { $0[page] } ?? Self.anyPage.withLock { $0 }
        guard let reply, !reply.transportError, let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Hevy API client paging", .serialized)
struct HevyAPIClientTests {
    private static func workoutJSON(id: String, title: String) -> String {
        """
        { "id": "\(id)", "title": "\(title)", "start_time": "2024-05-01T10:00:00Z",
          "exercises": [ { "title": "Squat", "sets": [ { "type": "normal", "weight_kg": 100, "reps": 5 } ] } ]
        }
        """
    }

    private static func page(_ number: Int, of total: Int, workouts: [String]) -> HevyStubProtocol.Reply {
        let list = workouts.joined(separator: ",")
        let body = #"{ "page": \#(number), "page_count": \#(total), "workouts": [\#(list)] }"#
        return .init(status: 200, body: body)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HevyStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("every page is fetched in order and mapped, and the key travels in the api-key header")
    func pagesInOrder() async {
        HevyStubProtocol.reset([
            1: Self.page(1, of: 2, workouts: [Self.workoutJSON(id: "w1", title: "Push")]),
            2: Self.page(2, of: 2, workouts: [Self.workoutJSON(id: "w2", title: "Pull")])
        ])
        let result = await HevyAPIClient.fetchAllWorkouts(apiKey: "secret", urlSession: session())
        #expect(result.problems.isEmpty)
        #expect(result.workouts.map(\.externalID) == ["w1", "w2"])
        #expect(result.workouts.map(\.title) == ["Push", "Pull"])
        let requests = HevyStubProtocol.seenRequests.withLock { $0 }
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "api-key") == "secret" })
        #expect(requests.first?.url?.query?.contains("pageSize=10") == true)
    }

    @Test("a rejected key stops the fetch with a problem naming the key, keeping nothing")
    func unauthorized() async {
        HevyStubProtocol.reset([1: .init(status: 401, body: "")])
        let result = await HevyAPIClient.fetchAllWorkouts(apiKey: "bad", urlSession: session())
        #expect(result.workouts.isEmpty)
        #expect(result.problems.map(\.message) == ["That API key was rejected by Hevy."])
        #expect(result.problems.first?.line == 1)
    }

    @Test("a server error on page 2 keeps page 1 and reports the status code against page 2")
    func serverErrorMidway() async {
        HevyStubProtocol.reset([
            1: Self.page(1, of: 3, workouts: [Self.workoutJSON(id: "w1", title: "Push")]),
            2: .init(status: 503, body: "")
        ])
        let result = await HevyAPIClient.fetchAllWorkouts(apiKey: "k", urlSession: session())
        #expect(result.workouts.map(\.externalID) == ["w1"])
        #expect(result.problems.map(\.line) == [2])
        #expect(result.problems.first?.message == "Hevy returned an error (503).")
        #expect(HevyStubProtocol.seenRequests.withLock { $0.count } == 2)
    }

    @Test("a page that isn't Hevy's JSON is reported as not understood")
    func decodingFailure() async {
        HevyStubProtocol.reset([1: .init(status: 200, body: #"{"unexpected": true}"#)])
        let result = await HevyAPIClient.fetchAllWorkouts(apiKey: "k", urlSession: session())
        #expect(result.workouts.isEmpty)
        #expect(result.problems.first?.message == "Couldn't understand Hevy's response.")
    }

    @Test("a bad timestamp in one workout fails the whole page rather than a silent skip")
    func badDateIsADecodingFailure() async {
        let workout = #"{ "id": "x", "title": "T", "start_time": "yesterday", "exercises": [] }"#
        let body = #"{ "page": 1, "page_count": 1, "workouts": [\#(workout)] }"#
        HevyStubProtocol.reset([1: .init(status: 200, body: body)])
        let result = await HevyAPIClient.fetchAllWorkouts(apiKey: "k", urlSession: session())
        #expect(result.workouts.isEmpty)
        #expect(result.problems.first?.message == "Couldn't understand Hevy's response.")
    }

    /// The parser moved from two `ISO8601DateFormatter`s per date to two hoisted `FormatStyle`s;
    /// the shapes Hevy actually sends — `Z`, a `+00:00` offset, with and without fractional
    /// seconds — must still parse, and a bare date must still fail.
    @Test("Hevy's timestamp shapes parse with and without fractional seconds and offsets")
    func dateShapes() {
        let expected = Date(timeIntervalSince1970: 1_714_557_600) // 2024-05-01T10:00:00Z
        #expect(HevyDateFormat.date(from: "2024-05-01T10:00:00Z") == expected)
        #expect(HevyDateFormat.date(from: "2024-05-01T10:00:00.000Z") == expected)
        #expect(HevyDateFormat.date(from: "2024-05-01T12:00:00+02:00") == expected)
        #expect(HevyDateFormat.date(from: "2024-05-01T12:00:00.250+02:00")
            == expected.addingTimeInterval(0.25))
        #expect(HevyDateFormat.date(from: "2024-05-01") == nil)
        #expect(HevyDateFormat.date(from: "yesterday") == nil)
    }

    @Test("a transport failure surfaces the system's own description")
    func transportFailure() async {
        HevyStubProtocol.reset([:])
        let result = await HevyAPIClient.fetchAllWorkouts(apiKey: "k", urlSession: session())
        #expect(result.workouts.isEmpty)
        #expect(result.problems.count == 1)
        #expect(result.problems.first?.message == URLError(.notConnectedToInternet).localizedDescription)
    }

    @Test("an endless page_count stops at the client's hard cap of 200 pages")
    func hardPageCap() async {
        HevyStubProtocol.reset([:])
        HevyStubProtocol.anyPage.withLock {
            $0 = Self.page(1, of: 100_000, workouts: [Self.workoutJSON(id: "w", title: "Loop")])
        }
        let result = await HevyAPIClient.fetchAllWorkouts(apiKey: "k", urlSession: session())
        #expect(result.problems.isEmpty)
        #expect(result.workouts.count == 200)
        #expect(HevyStubProtocol.seenRequests.withLock { $0.count } == 200)
    }

    @Test("a page_count of 0 still fetches page 1 and stops there")
    func zeroPageCount() async {
        let only = Self.workoutJSON(id: "w1", title: "Solo")
        HevyStubProtocol.reset([1: Self.page(1, of: 0, workouts: [only])])
        let result = await HevyAPIClient.fetchAllWorkouts(apiKey: "k", urlSession: session())
        #expect(result.workouts.count == 1)
        #expect(result.problems.isEmpty)
        #expect(HevyStubProtocol.seenRequests.withLock { $0.count } == 1)
    }
}
