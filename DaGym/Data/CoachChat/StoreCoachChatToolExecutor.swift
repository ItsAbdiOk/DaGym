import Foundation
import GymCore

/// `CoachChatToolExecutor` over a `WorkoutStore`: every tool in `CoachChatToolCatalog`, answered
/// from the store accessors the rest of the app already reads and returned as compact JSON
/// (ISO day dates, kg on the half-kilo, no nulls, lists capped with a `truncated` flag). The
/// `propose_*` tools decode straight into their `CoachChatDraft` proposal, validate against the
/// library and the lifter's equipment, and hand back a draft for the card — or throw with every
/// reason, which the engine sends to the model as `{"error": …}` so it can fix them and retry.
///
/// `now` and `calendar` are injected so a test can pin every window and date this writes.
@MainActor
final class StoreCoachChatToolExecutor: CoachChatToolExecutor {
    let store: WorkoutStore
    let unit: WeightUnit
    /// `Preferences.weeklyGoal`, for the adherence tool's streak.
    let weeklyGoal: Int
    let calendar: Calendar
    let now: () -> Date

    /// Sessions the history tools return at most before flagging `truncated`.
    static let maxSeriesSessions = 60
    static let defaultSearchResults = 40

    init(
        store: WorkoutStore, unit: WeightUnit, weeklyGoal: Int = 4, calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.unit = unit
        self.weeklyGoal = weeklyGoal
        self.calendar = calendar
        self.now = now
    }

    func execute(name: String, argumentsJSON: String) async throws -> CoachChatToolResult {
        guard let tool = CoachChatToolName(rawValue: name) else {
            throw CoachChatToolError.unknownTool(name)
        }
        let state = storeSignposter.beginInterval("coachChatTool")
        defer { storeSignposter.endInterval("coachChatTool", state) }
        return try handler(for: tool)(self, argumentsJSON)
    }

    /// One closure per tool: decode the arguments the schema promises, answer, encode. A table
    /// rather than a switch so adding a tool is one line and the catalogue test can check that
    /// every name has a handler.
    typealias Handler = @MainActor (StoreCoachChatToolExecutor, String) throws -> CoachChatToolResult

    static let handlers: [CoachChatToolName: Handler] = [
        .getProfile: { executor, _ in try executor.json(executor.profile()) },
        .listRoutines: { executor, _ in try executor.json(["routines": executor.listRoutines()]) },
        .getRoutine: read(RoutineArguments.self) { try $0.routine(id: $1) },
        .getSchedule: { executor, _ in try executor.json(executor.schedule()) },
        .getRecentWorkouts: read(LimitArguments.self) { $0.recentWorkouts($1) },
        .getWorkout: read(WorkoutArguments.self) { try $0.workout($1) },
        .getExerciseHistory: read(ExerciseArguments.self) { try $0.exerciseHistory($1) },
        .forecastE1RM: read(ForecastArguments.self) { try $0.forecast($1) },
        .getWeeklyVolume: read(WeeksArguments.self) { $0.weeklyVolume($1) },
        .getMuscleVolume: read(WeeksArguments.self) { $0.muscleVolume($1) },
        .getPersonalRecords: read(ExerciseArguments.self) { try $0.personalRecords($1) },
        .getAdherence: read(WeeksArguments.self) { $0.adherence($1) },
        .getRecovery: { executor, _ in try executor.json(executor.recovery()) },
        .getBodyMeasurements: read(WeeksArguments.self) { $0.bodyMeasurements($1) },
        .searchExercises: read(SearchArguments.self) { try $0.searchExercises($1) },
        .proposeRoutine: proposal(RoutineProposal.self, CoachChatDraft.routine),
        .proposeProgram: proposal(ProgramProposal.self, CoachChatDraft.program),
        .proposeSchedule: proposal(ScheduleProposal.self, CoachChatDraft.schedule),
        .proposeDeload: proposal(DeloadProposal.self, CoachChatDraft.deload),
        .proposeSwap: proposal(SwapProposal.self, CoachChatDraft.swap)
    ]

    private func handler(for tool: CoachChatToolName) throws -> Handler {
        guard let handler = Self.handlers[tool] else { throw CoachChatToolError.unknownTool(tool.rawValue) }
        return handler
    }

    private static func read<Arguments: Decodable, Payload: Encodable>(
        _ type: Arguments.Type,
        _ answer: @escaping @MainActor (StoreCoachChatToolExecutor, Arguments) throws -> Payload
    ) -> Handler {
        { executor, json in try executor.json(answer(executor, try executor.decode(type, json))) }
    }

    private static func proposal<Proposal: Decodable>(
        _ type: Proposal.Type, _ wrap: @escaping (Proposal) -> CoachChatDraft
    ) -> Handler {
        { executor, json in try executor.propose(wrap(try executor.decode(type, json))) }
    }

    // MARK: - Arguments

    struct RoutineArguments: Decodable {
        var routineID: UUID
        enum CodingKeys: String, CodingKey { case routineID = "routine_id" }
    }

    struct WorkoutArguments: Decodable {
        var workoutID: UUID
        enum CodingKeys: String, CodingKey { case workoutID = "workout_id" }
    }

    struct LimitArguments: Decodable {
        var limit: Int?
    }

    struct WeeksArguments: Decodable {
        var weeks: Int?

        /// Clamped to what the schema advertises, whatever the model sent.
        var clampedWeeks: Int {
            let range = CoachChatToolCatalog.weeksRange
            return min(max(weeks ?? CoachChatToolCatalog.defaultWeeks, range.lowerBound), range.upperBound)
        }
    }

    struct ExerciseArguments: Decodable {
        var exerciseID: UUID?
        var exerciseName: String?
        enum CodingKeys: String, CodingKey {
            case exerciseID = "exercise_id"
            case exerciseName = "exercise_name"
        }
    }

    struct ForecastArguments: Decodable {
        var exerciseID: UUID?
        var exerciseName: String?
        var targetKg: Double
        enum CodingKeys: String, CodingKey {
            case exerciseID = "exercise_id"
            case exerciseName = "exercise_name"
            case targetKg = "target_kg"
        }
    }

    struct SearchArguments: Decodable {
        var query: String?
        var muscle: String?
        var equipment: String?
        var machine: String?
        var allowedOnly: Bool?
        var limit: Int?

        enum CodingKeys: String, CodingKey {
            case query, muscle, equipment, machine, limit
            case allowedOnly = "allowed_only"
        }
    }

    /// Empty arguments (`""`, `"{}"`) decode as an empty object, so a no-argument tool never
    /// fails on a missing body; anything else must be the JSON object the schema describes.
    func decode<Arguments: Decodable>(_ type: Arguments.Type, _ json: String) throws -> Arguments {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data((trimmed.isEmpty ? "{}" : trimmed).utf8)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CoachChatToolError.badArguments(Self.describe(error))
        }
    }

    /// The part of a `DecodingError` the model can act on ("missing target_kg"), not the dump.
    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .keyNotFound(let key, _): return "missing \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default: return error.localizedDescription
        }
    }

    // MARK: - Output

    /// Sorted keys so a test can pin the exact text; dates as calendar days; `/` unescaped.
    func json<Payload: Encodable>(_ payload: Payload) throws -> CoachChatToolResult {
        .json(try encodeJSON(payload))
    }

    func encodeJSON<Payload: Encodable>(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let calendar = calendar
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateKey.string(for: date, calendar: calendar))
        }
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CoachChatToolError.encoding
        }
        return text
    }

    /// Kilograms on the half-kilo grid, the finest step the app displays.
    static func kg(_ value: Double) -> Double { (value * 2).rounded() / 2 }

    static func kg(_ value: Double?) -> Double? { value.map { kg($0) } }

    /// Two decimals, for ratios the model reads (R², spent fractions).
    static func fraction(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    // MARK: - Exercise lookup

    /// The library exercise the model means: by id, else by exact name, else the library
    /// search's best match — reads are lenient where proposals are strict.
    func resolveExercise(id: UUID?, name: String?) throws -> ExerciseInfo {
        if let id {
            guard let model = store.fetchExerciseModel(id: id), WorkoutStore.isLive(model) else {
                throw CoachChatToolError.notFound(
                    "No exercise with id \(id.uuidString); use search_exercises."
                )
            }
            return ExerciseInfo(model: model)
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw CoachChatToolError.badArguments("give exercise_id or exercise_name")
        }
        let matches = store.exercises(matching: trimmed)
        if let exact = matches.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }
        guard let first = matches.first else {
            throw CoachChatToolError.notFound("No exercise called '\(trimmed)'; use search_exercises.")
        }
        return first
    }
}

/// What a tool can refuse with. The engine shows the model `localizedDescription`, so each
/// message says what to do next.
enum CoachChatToolError: LocalizedError, Equatable {
    case unknownTool(String)
    case badArguments(String)
    case notFound(String)
    /// A proposal failed validation; every reason, so one retry can fix them all.
    case rejected([String])
    case encoding

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): "Unknown tool '\(name)'. Use only the tools you were given."
        case .badArguments(let detail): "Bad arguments: \(detail)."
        case .notFound(let detail): detail
        case .rejected(let reasons): "Proposal rejected. " + reasons.joined(separator: " ")
        case .encoding: "Could not encode the result."
        }
    }
}
