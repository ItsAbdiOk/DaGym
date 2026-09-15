import Foundation

/// A change the coach model wants to make, as a value the lifter sees on a card and applies
/// or discards. The model reaches these only through the `propose_*` tools; each proposal type
/// is also that tool's argument shape (snake_case keys), so the executor decodes the arguments
/// into it and then runs `validate` — nothing the model says lands in the store unchecked.
public enum CoachChatDraft: Codable, Hashable, Sendable {
    case routine(RoutineProposal)
    case program(ProgramProposal)
    case schedule(ScheduleProposal)
    case deload(DeloadProposal)
    case swap(SwapProposal)

    /// One line for the card header.
    public var summary: String {
        switch self {
        case .routine(let proposal): proposal.summary
        case .program(let proposal): proposal.summary
        case .schedule(let proposal): proposal.summary
        case .deload(let proposal): proposal.summary
        case .swap(let proposal): proposal.summary
        }
    }

    /// The bounds every proposal is held to. Sets and reps are what a planned set can hold;
    /// the load cap is the app-wide one every other validator reads.
    public enum Limits {
        public static let repsRange = 1...50
        public static let setsPerExercise = 1...10
        public static let exercisesPerRoutine = 1...20
        public static let restSecondsRange = 0...600
        public static let rpeRange = 1.0...10.0
        public static let maxWeightKg = TrainingConstants.maxLoadKg
        public static let deloadPercentRange = 1.0...50.0
        public static let maxNameLength = ProgramDraft.maxNameLength
        public static let maxNotesLength = 500
    }
}

/// Why a draft was refused: every reason, not just the first, so the model can fix them all in
/// one retry ("Unknown exercise 'Pendlay Row'; 'Leg Press' needs a Leg Press machine").
public struct CoachChatDraftRejection: Error, Hashable, Sendable {
    public var reasons: [String]

    public init(reasons: [String]) {
        self.reasons = reasons
    }
}

// MARK: - Building blocks

/// One planned set as the model describes it. Weight is optional — a bodyweight or first-time
/// exercise has none — and RPE is a target, not a log.
public struct CoachChatSetSpec: Codable, Hashable, Sendable {
    public var kind: SetKind
    public var targetReps: Int
    public var targetWeightKg: Double?
    public var rpe: Double?

    public init(
        kind: SetKind = .working, targetReps: Int, targetWeightKg: Double? = nil, rpe: Double? = nil
    ) {
        self.kind = kind
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.rpe = rpe
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case targetReps = "target_reps"
        case targetWeightKg = "target_weight_kg"
        case rpe
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(SetKind.self, forKey: .kind) ?? .working
        targetReps = try container.decode(Int.self, forKey: .targetReps)
        targetWeightKg = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
    }
}

/// One exercise in a proposed routine, named by library id or by name. After `validate` the
/// id is always filled and the name is the library's spelling.
public struct CoachChatExerciseSpec: Codable, Hashable, Sendable {
    public var exerciseID: UUID?
    public var exerciseName: String?
    public var sets: [CoachChatSetSpec]
    public var restSeconds: Int?
    /// Exercises sharing a group number are performed as a superset.
    public var supersetGroup: Int?

    public init(
        exerciseID: UUID? = nil, exerciseName: String? = nil, sets: [CoachChatSetSpec],
        restSeconds: Int? = nil, supersetGroup: Int? = nil
    ) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.sets = sets
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
    }

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case exerciseName = "exercise_name"
        case sets
        case restSeconds = "rest_seconds"
        case supersetGroup = "superset_group"
        // Shorthand the model may send instead of `sets`: one line per exercise instead of one
        // object per set. A four-routine program went from 3.7 KB of arguments to under 1 KB,
        // which is most of the time the model spent writing a proposal.
        case setCount = "set_count"
        case targetReps = "target_reps"
        case targetRepsHigh = "target_reps_high"
        case targetWeightKg = "target_weight_kg"
        case rpe
        case warmupSets = "warmup_sets"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try container.decodeIfPresent(UUID.self, forKey: .exerciseID)
        exerciseName = try container.decodeIfPresent(String.self, forKey: .exerciseName)
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        supersetGroup = try container.decodeIfPresent(Int.self, forKey: .supersetGroup)
        let explicit = try container.decodeIfPresent([CoachChatSetSpec].self, forKey: .sets) ?? []
        if !explicit.isEmpty {
            sets = explicit
            return
        }
        guard let count = try container.decodeIfPresent(Int.self, forKey: .setCount),
              let reps = try container.decodeIfPresent(Int.self, forKey: .targetReps) else {
            throw DecodingError.keyNotFound(
                CodingKeys.sets,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "give `sets`, or `set_count` with `target_reps`"
                )
            )
        }
        let weight = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        let rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        let warmups = try container.decodeIfPresent(Int.self, forKey: .warmupSets) ?? 0
        // Reps from `target_reps` to `target_reps_high` are spread evenly across the working sets
        // (the top of the range first — the ramp Apple's own strength apps use is heavier first).
        let high = try container.decodeIfPresent(Int.self, forKey: .targetRepsHigh) ?? reps
        let low = min(reps, high)
        var expanded: [CoachChatSetSpec] = []
        expanded.reserveCapacity(max(0, warmups) + max(0, count))
        for _ in 0..<max(0, min(warmups, 3)) {
            expanded.append(CoachChatSetSpec(kind: .warmup, targetReps: max(low, 8), targetWeightKg: nil))
        }
        for _ in 0..<max(0, count) {
            expanded.append(CoachChatSetSpec(targetReps: low, targetWeightKg: weight, rpe: rpe))
        }
        sets = expanded
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(exerciseID, forKey: .exerciseID)
        try container.encodeIfPresent(exerciseName, forKey: .exerciseName)
        try container.encode(sets, forKey: .sets)
        try container.encodeIfPresent(restSeconds, forKey: .restSeconds)
        try container.encodeIfPresent(supersetGroup, forKey: .supersetGroup)
    }

    /// What the card and a rejection call this exercise.
    public var label: String { exerciseName ?? exerciseID?.uuidString ?? "?" }
}

/// The progression rules the model may ask for, by short name. Mapped onto `ProgressionRule`
/// with the app's default increments; the store may refine the increment per exercise.
public enum CoachChatRuleChoice: String, Codable, CaseIterable, Hashable, Sendable {
    case linear
    case doubleProgression = "double_progression"
    case linearAMRAP = "linear_amrap"
    case rpe
    case bodyweight

    public func progressionRule(
        incrementKg: Double = TrainingConstants.defaultUpperBodyIncrementKg
    ) -> ProgressionRule {
        switch self {
        case .linear: .linear(incrementKg: incrementKg)
        case .doubleProgression: .doubleProgression(low: 8, high: 12, incrementKg: incrementKg)
        case .linearAMRAP: .linearAMRAP(incrementKg: incrementKg)
        case .rpe: .rpeBased(targetRPE: 8)
        case .bodyweight:
            .bodyweight(
                repCeiling: TrainingConstants.bodyweightRepCeiling,
                maxSets: TrainingConstants.bodyweightMaxSets
            )
        }
    }
}

// MARK: - Proposals

/// `propose_routine`'s arguments.
public struct RoutineProposal: Codable, Hashable, Sendable {
    public var name: String
    public var exercises: [CoachChatExerciseSpec]
    public var rule: CoachChatRuleChoice?
    public var notes: String?

    public init(
        name: String, exercises: [CoachChatExerciseSpec], rule: CoachChatRuleChoice? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.exercises = exercises
        self.rule = rule
        self.notes = notes
    }

    public var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    public var summary: String {
        "\(name) — \(exercises.count) \(exercises.count == 1 ? "exercise" : "exercises"), \(setCount) sets"
    }
}

/// `propose_program`'s arguments. With no `routines`, the app fills the goal's own template
/// (`ProgramTemplateEngine`) from the lifter's equipment; with them, they are the program.
public struct ProgramProposal: Codable, Hashable, Sendable {
    public var name: String
    public var goal: TrainingGoal
    public var daysPerWeek: Int
    public var experience: ExperienceLevel?
    public var sessionMinutes: Int?
    public var routines: [RoutineProposal]

    public init(
        name: String, goal: TrainingGoal, daysPerWeek: Int, experience: ExperienceLevel? = nil,
        sessionMinutes: Int? = nil, routines: [RoutineProposal] = []
    ) {
        self.name = name
        self.goal = goal
        self.daysPerWeek = daysPerWeek
        self.experience = experience
        self.sessionMinutes = sessionMinutes
        self.routines = routines
    }

    enum CodingKeys: String, CodingKey {
        case name, goal, experience, routines
        case daysPerWeek = "days_per_week"
        case sessionMinutes = "session_minutes"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        goal = try container.decode(TrainingGoal.self, forKey: .goal)
        daysPerWeek = try container.decode(Int.self, forKey: .daysPerWeek)
        experience = try container.decodeIfPresent(ExperienceLevel.self, forKey: .experience)
        sessionMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionMinutes)
        routines = try container.decodeIfPresent([RoutineProposal].self, forKey: .routines) ?? []
    }

    public var usesTemplate: Bool { routines.isEmpty }

    public var summary: String {
        let source = usesTemplate
            ? "from the \(goal.displayName.lowercased()) template" : "\(routines.count) routines"
        return "\(name) — \(daysPerWeek) days/week, \(source)"
    }
}

/// `propose_schedule`'s arguments: a routine per weekday; days left out are rest days.
/// `routineNames` is filled by the app after decoding so the card can print names.
public struct ScheduleProposal: Codable, Hashable, Sendable {
    public var days: [Weekday: UUID]
    public var routineNames: [UUID: String]

    public init(days: [Weekday: UUID], routineNames: [UUID: String] = [:]) {
        self.days = days
        self.routineNames = routineNames
    }

    enum CodingKeys: String, CodingKey {
        case days
        case routineNames = "routine_names"
    }

    /// Weekday keys on the wire are lowercase English names.
    public static func weekday(named name: String) -> Weekday? {
        Weekday.allCases.first { $0.displayName.lowercased() == name.lowercased() }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: String].self, forKey: .days)
        var days: [Weekday: UUID] = [:]
        for (key, value) in raw {
            guard let day = Self.weekday(named: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .days, in: container, debugDescription: "Unknown weekday '\(key)'"
                )
            }
            guard let id = UUID(uuidString: value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .days, in: container, debugDescription: "'\(value)' is not a routine id"
                )
            }
            days[day] = id
        }
        self.days = days
        let names = try container.decodeIfPresent([String: String].self, forKey: .routineNames) ?? [:]
        routineNames = Dictionary(
            names.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let raw = Dictionary(
            days.map { ($0.key.displayName.lowercased(), $0.value.uuidString) },
            uniquingKeysWith: { first, _ in first }
        )
        try container.encode(raw, forKey: .days)
        let names = Dictionary(
            routineNames.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { first, _ in first }
        )
        try container.encode(names, forKey: .routineNames)
    }

    public var summary: String {
        let parts = Weekday.ordered(mondayFirst: true).compactMap { day -> String? in
            guard let id = days[day] else { return nil }
            return "\(day.shortLabel) \(routineNames[id] ?? "routine")"
        }
        return parts.isEmpty ? "Every day a rest day" : parts.joined(separator: ", ")
    }
}

/// `propose_deload`'s arguments: back one exercise's working weight off by a percentage.
public struct DeloadProposal: Codable, Hashable, Sendable {
    public var exerciseID: UUID?
    public var exerciseName: String?
    public var percent: Double

    public init(exerciseID: UUID? = nil, exerciseName: String? = nil, percent: Double) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.percent = percent
    }

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case exerciseName = "exercise_name"
        case percent
    }

    public var summary: String {
        "Deload \(exerciseName ?? "exercise") by \(Int(percent.rounded()))%"
    }
}

/// `propose_swap`'s arguments: replace one exercise in one routine with another.
public struct SwapProposal: Codable, Hashable, Sendable {
    public var routineID: UUID
    public var routineName: String?
    public var fromExerciseID: UUID?
    public var fromExerciseName: String?
    public var toExerciseID: UUID?
    public var toExerciseName: String?

    public init(
        routineID: UUID, routineName: String? = nil, fromExerciseID: UUID? = nil,
        fromExerciseName: String? = nil, toExerciseID: UUID? = nil, toExerciseName: String? = nil
    ) {
        self.routineID = routineID
        self.routineName = routineName
        self.fromExerciseID = fromExerciseID
        self.fromExerciseName = fromExerciseName
        self.toExerciseID = toExerciseID
        self.toExerciseName = toExerciseName
    }

    enum CodingKeys: String, CodingKey {
        case routineID = "routine_id"
        case routineName = "routine_name"
        case fromExerciseID = "from_exercise_id"
        case fromExerciseName = "from_exercise_name"
        case toExerciseID = "to_exercise_id"
        case toExerciseName = "to_exercise_name"
    }

    public var summary: String {
        "Swap \(fromExerciseName ?? "exercise") → \(toExerciseName ?? "exercise") "
            + "in \(routineName ?? "routine")"
    }
}
