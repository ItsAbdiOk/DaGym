import Foundation

/// The subset of JSON Schema an OpenAI-style function definition needs, as a Codable value —
/// no `[String: Any]`, so the catalogue is Hashable, Sendable and round-trips through
/// `JSONEncoder` in a test. Encodes to exactly the shape the API expects
/// (`{"type":"object","properties":{…},"required":[…]}`); nil fields are left out.
public struct CoachChatToolSchema: Codable, Hashable, Sendable {
    /// One JSON-Schema type: "object", "array", "string", "integer", "number" or "boolean".
    public var type: String
    public var description: String?
    public var properties: [String: CoachChatToolSchema]?
    public var required: [String]?
    /// The element schema of an array. Boxed because a struct cannot contain itself directly.
    public var items: Box?
    /// The closed set of allowed string values.
    public var `enum`: [String]?
    public var minimum: Double?
    public var maximum: Double?
    /// Set false on every object so the model cannot smuggle keys the executor ignores.
    public var additionalProperties: Bool?

    public init(
        type: String, description: String? = nil, properties: [String: CoachChatToolSchema]? = nil,
        required: [String]? = nil, items: CoachChatToolSchema? = nil, enum: [String]? = nil,
        minimum: Double? = nil, maximum: Double? = nil, additionalProperties: Bool? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items.map(Box.init)
        self.enum = `enum`
        self.minimum = minimum
        self.maximum = maximum
        self.additionalProperties = additionalProperties
    }

    /// The array element schema, unboxed.
    public var itemSchema: CoachChatToolSchema? { items?.schema }

    /// An immutable reference wrapper so `items` can hold another schema. Encodes transparently
    /// as the schema itself.
    public final class Box: Codable, Hashable, Sendable {
        public let schema: CoachChatToolSchema

        public init(_ schema: CoachChatToolSchema) {
            self.schema = schema
        }

        public init(from decoder: Decoder) throws {
            schema = try decoder.singleValueContainer().decode(CoachChatToolSchema.self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(schema)
        }

        public static func == (lhs: Box, rhs: Box) -> Bool { lhs.schema == rhs.schema }

        public func hash(into hasher: inout Hasher) { hasher.combine(schema) }
    }

    // MARK: - Builders

    /// An object with `additionalProperties: false`, so the API rejects invented keys.
    public static func object(
        _ description: String? = nil, properties: [String: CoachChatToolSchema], required: [String] = []
    ) -> CoachChatToolSchema {
        CoachChatToolSchema(
            type: "object", description: description, properties: properties,
            required: required.isEmpty ? nil : required, additionalProperties: false
        )
    }

    public static func string(_ description: String, enum values: [String]? = nil) -> CoachChatToolSchema {
        CoachChatToolSchema(type: "string", description: description, enum: values)
    }

    public static func integer(
        _ description: String, in range: ClosedRange<Int>? = nil
    ) -> CoachChatToolSchema {
        CoachChatToolSchema(
            type: "integer", description: description,
            minimum: range.map { Double($0.lowerBound) }, maximum: range.map { Double($0.upperBound) }
        )
    }

    public static func number(
        _ description: String, in range: ClosedRange<Double>? = nil
    ) -> CoachChatToolSchema {
        CoachChatToolSchema(
            type: "number", description: description, minimum: range?.lowerBound, maximum: range?.upperBound
        )
    }

    public static func boolean(_ description: String) -> CoachChatToolSchema {
        CoachChatToolSchema(type: "boolean", description: description)
    }

    public static func array(_ description: String, of element: CoachChatToolSchema) -> CoachChatToolSchema {
        CoachChatToolSchema(type: "array", description: description, items: element)
    }
}

/// One tool the coach may call: the `function` object of an OpenAI tool definition. The
/// Services slice wraps it as `{"type":"function","function":<this>}`; the Store slice
/// implements it by `name`.
public struct CoachChatTool: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var description: String
    public var parameters: CoachChatToolSchema

    public var id: String { name }

    public init(name: CoachChatToolName, description: String, parameters: CoachChatToolSchema) {
        self.name = name.rawValue
        self.description = description
        self.parameters = parameters
    }
}

/// Every tool by its wire name. The executor switches on this; an unknown name from the model
/// is an error result, not a crash.
public enum CoachChatToolName: String, CaseIterable, Codable, Hashable, Sendable {
    case getProfile = "get_profile"
    case listRoutines = "list_routines"
    case getRoutine = "get_routine"
    case getSchedule = "get_schedule"
    case getRecentWorkouts = "get_recent_workouts"
    case getWorkout = "get_workout"
    case getExerciseHistory = "get_exercise_history"
    case forecastE1RM = "forecast_e1rm"
    case getWeeklyVolume = "get_weekly_volume"
    case getMuscleVolume = "get_muscle_volume"
    case getPersonalRecords = "get_personal_records"
    case getAdherence = "get_adherence"
    case getRecovery = "get_recovery"
    case getBodyMeasurements = "get_body_measurements"
    case searchExercises = "search_exercises"
    case proposeRoutine = "propose_routine"
    case proposeProgram = "propose_program"
    case proposeSchedule = "propose_schedule"
    case proposeDeload = "propose_deload"
    case proposeSwap = "propose_swap"
    /// Reviewer-only: the second model's way of saying the drafter's proposal stands.
    case agreeWithProposal = "agree_with_proposal"

    /// True for the tools that build a `CoachChatDraft` rather than read data.
    public var isProposal: Bool { rawValue.hasPrefix("propose_") }

    /// True for the tools only the second-opinion model is offered.
    public var isReviewerOnly: Bool { self == .agreeWithProposal }

    /// The one-line label the chat shows while the tool runs ("Reading bench history").
    public var activityLabel: String {
        switch self {
        case .getProfile: "Reading your profile"
        case .listRoutines: "Listing routines"
        case .getRoutine: "Reading a routine"
        case .getSchedule: "Reading your schedule"
        case .getRecentWorkouts: "Reading recent workouts"
        case .getWorkout: "Reading a workout"
        case .getExerciseHistory: "Reading exercise history"
        case .forecastE1RM: "Forecasting progress"
        case .getWeeklyVolume: "Reading weekly volume"
        case .getMuscleVolume: "Reading muscle volume"
        case .getPersonalRecords: "Reading personal records"
        case .getAdherence: "Reading adherence"
        case .getRecovery: "Reading recovery"
        case .getBodyMeasurements: "Reading body measurements"
        case .searchExercises: "Searching exercises"
        case .proposeRoutine: "Drafting a routine"
        case .proposeProgram: "Drafting a program"
        case .proposeSchedule: "Drafting a schedule"
        case .proposeDeload: "Drafting a deload"
        case .proposeSwap: "Drafting a swap"
        case .agreeWithProposal: "Agreeing with the proposal"
        }
    }
}
