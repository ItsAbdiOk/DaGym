import Foundation
import GymCore

/// Whether a `CoachLanguageModel` can answer right now, with a one-line reason when it can't —
/// shown verbatim in Settings ("On-device AI: unavailable — Apple Intelligence is off").
enum CoachModelAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool { self == .available }
}

/// What the "Ask about your training" feature returns: the sentence to show, the tool results
/// it was built from, and whether `CoachAnswerValidator` let it through. When it didn't, the
/// caller shows the tool results themselves — numbers the store produced — rather than a
/// sentence with a number the model made up.
struct CoachAnswer: Equatable, Sendable {
    var text: String
    var toolResults: [CoachToolResult]
    var isGrounded: Bool
}

/// The app-side source of numbers for the question tools. `WorkoutStore` implements it; tests
/// hand in a fake. Main-actor because the store is; `FoundationCoachModel`'s tools hop over.
@MainActor
protocol CoachToolAnswering: AnyObject, Sendable {
    /// Library exercise names, for the model's exercise-name arguments and the rule matcher.
    var exerciseNamesForCoach: [String] { get }
    func answerCoachQuery(_ query: CoachToolQuery) -> CoachToolResult
}

/// The boundary between DaGym and any language model (plan.md §6.6). One method per feature,
/// each taking pre-summarised GymCore input and returning a plain GymCore result the matching
/// validator has already accepted — so a caller can't tell (and needn't care) whether the words
/// came from Apple's on-device model or from `RuleCoachModel`'s thresholds. Nothing here takes
/// raw history, and nothing here takes HealthKit-derived values.
protocol CoachLanguageModel: Sendable {
    var availability: CoachModelAvailability { get }

    /// Streams progressively fuller debriefs; the last element is the validated final one.
    /// Finishes with no elements when the validator rejected everything.
    func debrief(facts: SessionSummaryFacts) -> AsyncThrowingStream<SessionDebrief, Error>

    /// Reorders `candidates` (never adds to them) for `reason`, one line of why per pick.
    func rankSubstitutes(
        for exercise: SubstitutionCandidate, reason: String, candidates: [ScoredSubstitute],
        recoveryMap: [Muscle: Double]
    ) async throws -> [RankedSubstitute]

    /// Fills the template's slots from `pool` and names the program; validated before return.
    func draftProgram(
        template: ProgramTemplate, pool: [SubstitutionCandidate], request: ProgramRequest
    ) async throws -> ProgramDraft

    /// Up to three validated changes for the digest.
    func reviewTraining(digest: TrainingDigest) async throws -> [ReviewProposal]

    /// Answers one question using only numbers `tools` returned.
    func answer(question: String, tools: any CoachToolAnswering) async throws -> CoachAnswer
}

/// The one place the app decides which model it's talking to: Apple's on-device model when the
/// lifter has it on and the system says it's ready, `RuleCoachModel` otherwise. Observable so
/// Settings' status line and the Coach screens re-read after a toggle or a foreground.
@MainActor
@Observable
final class CoachServices {
    private(set) var model: any CoachLanguageModel
    /// "On-device AI: ready" / "On-device AI: unavailable — …", for Settings.
    private(set) var statusLine: String

    init(model: any CoachLanguageModel, statusLine: String) {
        self.model = model
        self.statusLine = statusLine
    }

    /// Picks the model for the current preferences and device state.
    static func make(preferences: Preferences) -> CoachServices {
        let services = CoachServices(model: RuleCoachModel(), statusLine: "")
        services.refresh(preferences: preferences)
        return services
    }

    func refresh(preferences: Preferences) {
        let foundation = FoundationCoachModel()
        switch (preferences.onDeviceCoachEnabled, foundation.availability) {
        case (true, .available):
            model = foundation
            statusLine = "On-device AI: ready"
        case (true, .unavailable(let reason)):
            model = RuleCoachModel()
            statusLine = "On-device AI: unavailable — \(reason)"
        case (false, _):
            model = RuleCoachModel()
            statusLine = "On-device AI: off — rule-based coach only"
        }
    }

    /// True when the words on screen come from the language model rather than the rules —
    /// the Coach screens say which, since the two read differently.
    var isUsingLanguageModel: Bool { model.availability.isAvailable && model is FoundationCoachModel }
}
