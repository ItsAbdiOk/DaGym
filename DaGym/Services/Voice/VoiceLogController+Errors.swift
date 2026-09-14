import Foundation
import GymCore

/// Turning a `VoiceCommandParser`/`LogCommandValidator` outcome into one of
/// `VoiceLogController.VoiceLogError`'s specific, actionable states.
extension VoiceLogController {
    /// `ExerciseMatcher` always returns its top 3 candidates from whatever pool it was given, even
    /// when none of them are a real match — `buildContext` scopes `ParseContext.library` to the
    /// current session, so those candidates are always session exercises, never "the real thing,
    /// just not today's session". A best score below this floor means nothing in the session even
    /// resembles what was said; at or above it (but still under `ExerciseMatcher.threshold`, or
    /// the parser would have auto-resolved already), it's a genuine "which one did you mean" and
    /// maps to `.needsDisambiguation` instead — see `map(_:commands:)`.
    static let notInSessionScoreFloor = 0.4

    /// Before validation even runs: an exercise phrase whose best candidate score doesn't clear
    /// `notInSessionScoreFloor`.
    static func unresolvedExerciseNotInSession(_ commands: [LogCommand]) -> VoiceLogError? {
        for command in commands {
            guard case .spoken(let phrase, let candidates) = exerciseRef(in: command) else { continue }
            let best = candidates.first?.score ?? 0
            guard best < notInSessionScoreFloor else { continue }
            return .exerciseNotInSession(spoken: phrase)
        }
        return nil
    }

    static func exerciseRef(in command: LogCommand) -> ExerciseRef {
        switch command {
        case .logSet(let spec): spec.exercise ?? .onDeck
        case .swapExercise(_, let replacement): replacement
        case .addExercise(let exercise), .removeExercise(let exercise): exercise
        case .addNote(let exercise, _): exercise ?? .onDeck
        case .query(.lastSession(let exercise)), .query(.personalRecord(let exercise)): exercise ?? .onDeck
        default: .onDeck
        }
    }

    static func map(_ error: ValidationError, commands: [LogCommand]) -> VoiceLogError {
        switch error {
        case .needsDisambiguation(let candidates):
            let spoken = commands.lazy.compactMap { command -> String? in
                guard case .spoken(let phrase, _) = exerciseRef(in: command) else { return nil }
                return phrase
            }.first ?? ""
            return .needsDisambiguation(spoken: spoken, candidates: candidates.map(\.name))
        default:
            return .didNotUnderstand
        }
    }

    /// The auto-log gate. Every leg has to hold: the user opted in, we have a combined
    /// confidence at all (i.e. a final hypothesis with a real recognition score — see
    /// `VoiceAutoLogPolicy`), it clears the bar, and no validator flag asks for a second look.
    /// `.roundedToPlates` is fine — that's routine rounding, not a reason to stop and ask.
    static func isEligible(
        confidence: Double?, flags: [ValidationFlag], autoLogEnabled: Bool
    ) -> Bool {
        guard autoLogEnabled else { return false }
        guard let confidence, confidence >= VoiceAutoLogPolicy.minConfidence else { return false }
        return !flags.contains { flag in
            if case .needsConfirmation = flag { return true }
            if case .suspicious = flag { return true }
            return false
        }
    }
}
