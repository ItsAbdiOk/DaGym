import Foundation
import GymCore

/// Fetches workout history straight from the Hevy Pro REST API (a per-account API key from
/// hevy.app → Settings → API), mapping each page into the same `ImportedWorkout` shape the CSV
/// importers produce (`GymCore.WorkoutImport`) so `WorkoutImportService`'s existing preview/apply
/// path is reused unchanged (OpenGym parity 38 / Adopt-now 22). The key itself lives in the
/// Keychain (`KeychainStore`), never in `Preferences`/`UserDefaults`.
enum HevyAPIClient {
    /// `KeychainStore` account name the API key is stored under.
    static let keychainAccount = "hevyAPIKey"

    enum ClientError: Error, Equatable {
        case unauthorized
        case server(Int)
        case decoding
        case transport(String)
    }

    private static let baseURL = URL(string: "https://api.hevyapp.com/v1/workouts")
    private static let pageSize = 10
    /// Hard stop so a misbehaving server (or an account with an unbounded history) can't page
    /// forever; comfortably above what "8 weeks of sample data" or a few years of real training
    /// would ever need.
    private static let maxPages = 200

    /// Pages through every workout the key can see, mapping each into `ImportedWorkout` as it
    /// arrives. Stops at the first page that fails and reports it as a problem rather than
    /// throwing, so the caller always gets a preview — even an empty one with a clear reason —
    /// instead of an error alert with nothing to look at.
    static func fetchAllWorkouts(
        apiKey: String, urlSession: URLSession = .shared
    ) async -> (workouts: [ImportedWorkout], problems: [ImportProblem]) {
        var workouts: [ImportedWorkout] = []
        var problems: [ImportProblem] = []
        var page = 1
        var pageCount = 1
        while page <= pageCount, page <= maxPages {
            do {
                let response = try await fetchPage(page: page, apiKey: apiKey, urlSession: urlSession)
                workouts.append(contentsOf: response.workouts.map(map))
                pageCount = max(response.pageCount, 1)
            } catch {
                problems.append(ImportProblem(line: page, message: message(for: error)))
                break
            }
            page += 1
        }
        return (workouts, problems)
    }

    private static func fetchPage(
        page: Int, apiKey: String, urlSession: URLSession
    ) async throws -> HevyWorkoutsResponse {
        guard let baseURL else { throw ClientError.transport("Bad request URL.") }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        guard let url = components?.url else { throw ClientError.transport("Bad request URL.") }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ClientError.transport("No response.") }
        if http.statusCode == 401 { throw ClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.server(http.statusCode) }
        do {
            return try decoder.decode(HevyWorkoutsResponse.self, from: data)
        } catch {
            throw ClientError.decoding
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let container = try valueDecoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = HevyDateFormat.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(text)")
        }
        return decoder
    }()

    private static func message(for error: Error) -> String {
        switch error {
        case ClientError.unauthorized: "That API key was rejected by Hevy."
        case ClientError.server(let code): "Hevy returned an error (\(code))."
        case ClientError.decoding: "Couldn't understand Hevy's response."
        case ClientError.transport(let text): text
        default: "Something went wrong talking to Hevy."
        }
    }

    // MARK: - Mapping (unit-tested against a fixture in `FeatureHomeImportTests` — no network)

    /// Hevy's own workout `id` travels as `externalID`: it is the only stable identity the API
    /// gives us, and without it a paged fetch that overlaps (or a second run of the same import)
    /// has nothing but the start time to dedupe on.
    static func map(_ workout: HevyWorkout) -> ImportedWorkout {
        ImportedWorkout(
            startedAt: workout.startTime, endedAt: workout.endTime,
            title: workout.title, notes: workout.description ?? "", externalID: workout.id,
            exercises: workout.exercises.map(map)
        )
    }

    private static func map(_ exercise: HevyExercise) -> ImportedExercise {
        ImportedExercise(
            name: exercise.title, note: exercise.notes ?? "", category: nil,
            supersetGroup: exercise.supersetId, sets: exercise.sets.map(map)
        )
    }

    private static func map(_ set: HevySet) -> ImportedSet {
        ImportedSet(
            kind: kind(for: set.type), weightKg: set.weightKg ?? 0, reps: set.reps ?? 0,
            durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters, rpe: set.rpe
        )
    }

    private static func kind(for type: String?) -> SetKind {
        switch type?.lowercased() {
        case "warmup": .warmup
        case "dropset": .drop
        case "failure": .failure
        default: .working
        }
    }
}

/// Parses the ISO-8601 timestamps the Hevy API returns, with or without fractional seconds.
enum HevyDateFormat {
    // `Date.ISO8601FormatStyle` is a Sendable value, so the two styles are built once rather
    // than two `ISO8601DateFormatter`s per date parsed (which aren't Sendable, and so couldn't
    // be hoisted).
    private static let withFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractional = Date.ISO8601FormatStyle()

    static func date(from text: String) -> Date? {
        (try? withFractional.parse(text)) ?? (try? withoutFractional.parse(text))
    }
}

// MARK: - DTOs (Hevy API v1 `/v1/workouts` response shape)

struct HevyWorkoutsResponse: Decodable {
    var page: Int
    var pageCount: Int
    var workouts: [HevyWorkout]
}

struct HevyWorkout: Decodable {
    var id: String
    var title: String
    var description: String?
    var startTime: Date
    var endTime: Date?
    var exercises: [HevyExercise]
}

struct HevyExercise: Decodable {
    var title: String
    var notes: String?
    /// Hevy's superset grouping for this slot within the workout; nil when it wasn't a superset.
    var supersetId: Int?
    var sets: [HevySet]
}

struct HevySet: Decodable {
    var type: String?
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var rpe: Double?
}
