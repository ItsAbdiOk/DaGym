import Foundation

/// The one closed grammar every voice/text/Siri/watch input compiles to.
/// Nothing else may mutate a workout session from spoken or typed input.
public enum LogCommand: Hashable, Codable, Sendable {
    /// Complete (or create-and-complete) sets on an exercise.
    case logSet(LogSetSpec)
    /// "same again [but …]" — repeats the last completed set with overrides.
    case repeatPrevious(overrides: LogSetSpec.Overrides)
    /// "that felt like a 9" — attach effort to the most recently completed set.
    case rateLastSet(Effort)
    /// "no, eight not nine" / "actually that was 95" — corrects the last completed set.
    case correctLastSet(LogSetSpec.Overrides)
    /// "undo" / "scrap that".
    case undo
    /// "done" / "next" — completes the on-deck set as prefilled.
    case completeOnDeck
    /// "swap this for dumbbell press".
    case swapExercise(target: ExerciseRef?, replacement: ExerciseRef)
    /// "add lateral raises".
    case addExercise(ExerciseRef)
    /// "remove leg press".
    case removeExercise(ExerciseRef)
    /// "rest two minutes" / "skip rest" / "add thirty seconds".
    case rest(RestAction)
    /// "note left shoulder pinched on rep six".
    case addNote(exercise: ExerciseRef?, text: String)
    /// "what did I do last time" / "my pr".
    case query(Query)
}

/// One or more sets to log against an exercise.
public struct LogSetSpec: Hashable, Codable, Sendable {
    /// `nil` means the on-deck exercise.
    public var exercise: ExerciseRef?
    /// `nil` means the on-deck set's kind (usually `.working`).
    public var kind: SetKind?
    /// One entry for a single set; N for "3 sets of 8 at 60" or "10, 10, 8".
    public var sets: [SetValues]
    public var effort: Effort?
    /// "ten per side" / "eight each arm".
    public var isPerSide: Bool?

    public init(
        exercise: ExerciseRef? = nil,
        kind: SetKind? = nil,
        sets: [SetValues],
        effort: Effort? = nil,
        isPerSide: Bool? = nil
    ) {
        self.exercise = exercise
        self.kind = kind
        self.sets = sets
        self.effort = effort
        self.isPerSide = isPerSide
    }

    /// The reps/weight/duration values of a single set within a spec.
    public struct SetValues: Hashable, Codable, Sendable {
        public var reps: Int?
        /// Canonical kg; the validator converts from the user's spoken unit.
        public var weightKg: Double?
        public var durationSeconds: Int?
        /// "minus twenty" on an assisted movement.
        public var assistanceKg: Double?
        /// Weighted bodyweight, e.g. "with ten kilos".
        public var addedKg: Double?
        public var isBodyweight: Bool

        public init(
            reps: Int? = nil,
            weightKg: Double? = nil,
            durationSeconds: Int? = nil,
            assistanceKg: Double? = nil,
            addedKg: Double? = nil,
            isBodyweight: Bool = false
        ) {
            self.reps = reps
            self.weightKg = weightKg
            self.durationSeconds = durationSeconds
            self.assistanceKg = assistanceKg
            self.addedKg = addedKg
            self.isBodyweight = isBodyweight
        }
    }

    /// A delta/replacement patch applied to the previous or last-completed set.
    public struct Overrides: Hashable, Codable, Sendable {
        public var reps: Int?
        public var weightKg: Double?
        public var weightDeltaKg: Double?
        public var durationSeconds: Int?
        public var effort: Effort?

        public init(
            reps: Int? = nil,
            weightKg: Double? = nil,
            weightDeltaKg: Double? = nil,
            durationSeconds: Int? = nil,
            effort: Effort? = nil
        ) {
            self.reps = reps
            self.weightKg = weightKg
            self.weightDeltaKg = weightDeltaKg
            self.durationSeconds = durationSeconds
            self.effort = effort
        }
    }
}

/// A reference to an exercise, resolved or not.
public enum ExerciseRef: Hashable, Codable, Sendable {
    /// "this" — the on-deck exercise.
    case onDeck
    /// Resolved by the matcher to a single candidate.
    case id(UUID)
    /// Unresolved: the raw spoken phrase plus the matcher's candidates for disambiguation.
    case spoken(String, candidates: [ExerciseMatch])
}

/// One scored candidate produced by `ExerciseMatcher`.
public struct ExerciseMatch: Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var score: Double

    public init(id: UUID, name: String, score: Double) {
        self.id = id
        self.name = name
        self.score = score
    }
}

/// What the rest timer should do.
public enum RestAction: Hashable, Codable, Sendable {
    case start(seconds: Int?)
    case skip
    case adjust(deltaSeconds: Int)
}

/// A read-only question about training history.
public enum Query: Hashable, Codable, Sendable {
    case lastSession(ExerciseRef?)
    case personalRecord(ExerciseRef?)
}

/// A slot the parser could not fill with confidence; drives confirm-card copy.
public enum Unresolved: Hashable, Codable, Sendable {
    case exerciseAmbiguous
    case missingReps
    case missingWeight
    case unitUnknown
}

/// The parser's output for one utterance: zero or more commands plus how sure it is.
public struct ParseResult: Sendable {
    public var commands: [LogCommand]
    /// 0…1. `matchedPattern` names the §4.5 rule that fired, for tests/debugging.
    public var confidence: Double
    public var matchedPattern: String
    public var unresolved: [Unresolved]

    public init(
        commands: [LogCommand] = [],
        confidence: Double = 0,
        matchedPattern: String = "none",
        unresolved: [Unresolved] = []
    ) {
        self.commands = commands
        self.confidence = confidence
        self.matchedPattern = matchedPattern
        self.unresolved = unresolved
    }
}

/// Everything the parser and validator know about the current session, so
/// utterances like "eight at a hundred" or "same again" need no exercise name.
public struct ParseContext: Sendable {
    public var unit: WeightUnit
    public var onDeck: OnDeckSet?
    public var lastCompleted: CompletedSetRef?
    /// In-session exercises first — ranked boost in the matcher.
    public var sessionExercises: [ExerciseCandidate]
    /// The full library (curated + custom).
    public var library: [ExerciseCandidate]
    /// Curated + learned aliases; exact match short-circuits the matcher at score 1.0.
    public var aliases: [String: UUID]
    /// For "plates" / "two plates" phrasing.
    public var bar: Bar?
    public var plateSet: [PlateStock]
    public var effortScale: Effort.Scale

    public init(
        unit: WeightUnit,
        onDeck: OnDeckSet? = nil,
        lastCompleted: CompletedSetRef? = nil,
        sessionExercises: [ExerciseCandidate] = [],
        library: [ExerciseCandidate] = [],
        aliases: [String: UUID] = [:],
        bar: Bar? = .olympic,
        plateSet: [PlateStock] = PlateStock.standardKg,
        effortScale: Effort.Scale = .rpe
    ) {
        self.unit = unit
        self.onDeck = onDeck
        self.lastCompleted = lastCompleted
        self.sessionExercises = sessionExercises
        self.library = library
        self.aliases = aliases
        self.bar = bar
        self.plateSet = plateSet
        self.effortScale = effortScale
    }

    /// How a set logs when no reps/weight/duration is spoken: which fields exist
    /// and what they're prefilled with.
    public struct OnDeckSet: Sendable {
        public var exerciseID: UUID
        public var name: String
        public var loggingStyle: LoggingStyle
        public var isPerSide: Bool
        public var kind: SetKind
        public var prefilledWeightKg: Double?
        public var prefilledReps: Int?
        public var targetSeconds: Int?
        public var incrementKg: Double

        public init(
            exerciseID: UUID,
            name: String,
            loggingStyle: LoggingStyle,
            isPerSide: Bool = false,
            kind: SetKind = .working,
            prefilledWeightKg: Double? = nil,
            prefilledReps: Int? = nil,
            targetSeconds: Int? = nil,
            incrementKg: Double = 2.5
        ) {
            self.exerciseID = exerciseID
            self.name = name
            self.loggingStyle = loggingStyle
            self.isPerSide = isPerSide
            self.kind = kind
            self.prefilledWeightKg = prefilledWeightKg
            self.prefilledReps = prefilledReps
            self.targetSeconds = targetSeconds
            self.incrementKg = incrementKg
        }
    }

    /// How an exercise is tracked — drives which fields a bare utterance fills.
    public enum LoggingStyle: Sendable {
        case weightReps, bodyweightReps, timedHold, assisted
    }

    public struct CompletedSetRef: Sendable {
        public var exerciseID: UUID
        public var setID: UUID
        public var weightKg: Double?
        public var reps: Int?
        public var effort: Effort?
        public var durationSeconds: Int?

        public init(
            exerciseID: UUID,
            setID: UUID,
            weightKg: Double? = nil,
            reps: Int? = nil,
            effort: Effort? = nil,
            durationSeconds: Int? = nil
        ) {
            self.exerciseID = exerciseID
            self.setID = setID
            self.weightKg = weightKg
            self.reps = reps
            self.effort = effort
            self.durationSeconds = durationSeconds
        }
    }

    /// A library or session exercise the matcher can score against.
    public struct ExerciseCandidate: Sendable {
        public var id: UUID
        public var name: String
        public var equipment: String?
        public var isFavorite: Bool
        public var isInSession: Bool

        public init(
            id: UUID, name: String, equipment: String? = nil, isFavorite: Bool = false,
            isInSession: Bool = false
        ) {
            self.id = id
            self.name = name
            self.equipment = equipment
            self.isFavorite = isFavorite
            self.isInSession = isInSession
        }
    }
}
