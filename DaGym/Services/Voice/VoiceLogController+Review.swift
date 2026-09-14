import Foundation
import GymCore

/// The review card's "Log" button. Everything here exists because the card is an *editing*
/// surface: what it writes is whatever the user typed, which is exactly why it has to go through
/// `LogCommandValidator` like any other command rather than straight into the session.
extension VoiceLogController {
    /// Applies exactly what's shown in (or was edited into) the card, through the same
    /// validate-then-mutate path as an auto-log.
    func confirmReview(
        _ card: ReviewCard, session: WorkoutSession, store: WorkoutStore, preferences: Preferences,
        undo: @escaping (UndoAction) -> Void
    ) {
        guard let entryIndex = session.exercises.firstIndex(where: { $0.id == card.entryID }) else {
            state = .error(.unsupportedCommand)
            return
        }
        var spec = card.spec
        spec.sets = Self.editedSets(card)
        // Pin the exercise to the row the card is about: the card can outlive a change of
        // on-deck, and the validator rounds against the target exercise's own plate grid.
        spec.exercise = .id(session.exercises[entryIndex].exercise.id)

        let context = Self.buildContext(session: session, store: store, preferences: preferences)
        switch LogCommandValidator.validate([.logSet(spec)], in: context, hasUndoReceipt: false) {
        case .failure(let error):
            state = .error(Self.mapEdited(error))
        case .success(let validated):
            guard case .logSet(let checked)? = validated.first?.command else {
                state = .error(.valueOutOfRange)
                return
            }
            let target = VoiceLogWriteTarget(
                session: session, store: store, unit: preferences.weightUnit
            )
            apply(spec: checked, entryIndex: entryIndex, target: target) { result in
                undo(UndoAction(message: result.summary, undo: result.undo))
                self.state = .idle
            }
        }
    }

    /// The card shows one set's fields even when the utterance asked for several ("three sets of
    /// eight at sixty"), and it used to write exactly one of them with nothing to say so. All of
    /// them are written now — and a field the user *didn't* touch keeps each set's own parsed
    /// value, so a heterogeneous "10, 10, 8" isn't flattened by confirming the card.
    static func editedSets(_ card: ReviewCard) -> [LogSetSpec.SetValues] {
        let weightEdited = card.weightKg != card.parsed.weightKg
        let repsEdited = card.reps != card.parsed.reps
        let durationEdited = card.durationSeconds != card.parsed.durationSeconds
        let sets = card.spec.sets.isEmpty ? [card.parsed] : card.spec.sets
        return sets.map { values in
            var values = values
            if weightEdited { values.weightKg = card.weightKg }
            if repsEdited { values.reps = card.reps }
            if durationEdited { values.durationSeconds = card.durationSeconds }
            return values
        }
    }

    /// Validation failures on *edited* values are about the numbers in the fields, not about
    /// what was heard — "try saying it differently" would be nonsense copy here.
    static func mapEdited(_ error: ValidationError) -> VoiceLogError {
        switch error {
        case .repsOutOfBounds, .weightOutOfBounds, .durationOutOfBounds, .setsCountOutOfBounds,
             .implausibleWeight, .trackingStyleMismatch:
            return .valueOutOfRange
        default:
            return .didNotUnderstand
        }
    }
}
