import Foundation
import GymCore

/// Transcript → `VoiceCommandParser` → `LogCommandValidator` → either an auto-log or a review
/// card. Split out of `VoiceLogController.swift` to stay under the type-body-length cap.
extension VoiceLogController {
    func process(
        transcript: String, recognitionConfidence: Double?, turn: VoiceLogTurnContext
    ) {
        guard !transcript.isEmpty else { state = .error(.nothingHeard); return }

        let context = Self.buildContext(
            session: turn.session, store: turn.store, preferences: turn.preferences
        )
        let result = VoiceCommandParser.parse(transcript, context: context)
        guard !result.commands.isEmpty else { state = .error(.didNotUnderstand); return }

        if let notInSession = Self.unresolvedExerciseNotInSession(result.commands) {
            state = .error(notInSession)
            return
        }

        switch LogCommandValidator.validate(result.commands, in: context, hasUndoReceipt: false) {
        case .failure(let error):
            state = .error(Self.map(error, commands: result.commands))
        case .success(let validated):
            let confidence = VoiceAutoLogPolicy.combined(
                parser: result.confidence, recognition: recognitionConfidence
            )
            handle(validated: validated, confidence: confidence, transcript: transcript, turn: turn)
        }
    }

    private func handle(
        validated: [ValidatedCommand], confidence: Double?, transcript: String,
        turn: VoiceLogTurnContext
    ) {
        guard validated.count == 1, let only = validated.first else {
            state = .error(.unsupportedCommand)
            return
        }

        switch only.command {
        case .logSet(let spec):
            handleLogSet(
                spec, flags: only.flags, confidence: confidence, transcript: transcript, turn: turn
            )
        case .completeOnDeck:
            handleCompleteOnDeck(
                flags: only.flags, confidence: confidence, transcript: transcript, turn: turn
            )
        default:
            // Repeat/rate/correct/undo/swap/add/remove/rest/note/query: parsed correctly by
            // GymCore, but v1's app layer only ever writes a logSet/completeOnDeck — see
            // `VoiceLogError.unsupportedCommand`.
            state = .error(.unsupportedCommand)
        }
    }

    private func handleLogSet(
        _ spec: LogSetSpec, flags: [ValidationFlag], confidence: Double?, transcript: String,
        turn: VoiceLogTurnContext
    ) {
        guard let entryIndex = Self.resolveEntryIndex(exercise: spec.exercise, session: turn.session) else {
            state = .error(.unsupportedCommand)
            return
        }
        let eligible = Self.isEligible(
            confidence: confidence, flags: flags,
            autoLogEnabled: turn.preferences.voiceAutoLogEnabled
        )
        if spec.sets.count == 1, eligible {
            autoLog(spec: spec, entryIndex: entryIndex, turn: turn)
            return
        }
        state = .reviewing(Self.reviewCard(
            spec: spec, transcript: transcript, entryIndex: entryIndex,
            session: turn.session, unit: turn.preferences.weightUnit
        ))
    }

    /// "Done"/"next". It writes no new numbers — it completes the on-deck set exactly as
    /// prefilled — but it is still a silent write, so with auto-log off it goes through the same
    /// card as everything else, prefilled with the set's own values.
    private func handleCompleteOnDeck(
        flags: [ValidationFlag], confidence: Double?, transcript: String, turn: VoiceLogTurnContext
    ) {
        let session = turn.session
        guard let entryIndex = session.onDeckIndex,
              let setIndex = session.exercises[entryIndex].sets.firstIndex(where: { !$0.isDone }) else {
            state = .error(.unsupportedCommand)
            return
        }
        if Self.isEligible(
            confidence: confidence, flags: flags,
            autoLogEnabled: turn.preferences.voiceAutoLogEnabled
        ) {
            applyCompleteOnDeck(
                session: session, store: turn.store, preferences: turn.preferences, undo: turn.undo
            )
            return
        }
        let set = session.exercises[entryIndex].sets[setIndex]
        let spec = LogSetSpec(
            exercise: .id(session.exercises[entryIndex].exercise.id), kind: set.kind,
            sets: [LogSetSpec.SetValues(reps: set.reps, weightKg: set.weightKg)]
        )
        state = .reviewing(Self.reviewCard(
            spec: spec, transcript: transcript, entryIndex: entryIndex,
            session: session, unit: turn.preferences.weightUnit
        ))
    }

    private func autoLog(spec: LogSetSpec, entryIndex: Int, turn: VoiceLogTurnContext) {
        let preferences = turn.preferences
        let target = VoiceLogWriteTarget(
            session: turn.session, store: turn.store, unit: preferences.weightUnit
        )
        apply(spec: spec, entryIndex: entryIndex, target: target) { result in
            turn.undo(UndoAction(message: result.summary, undo: result.undo))
            self.state = .autoLogged(message: result.summary)
            if preferences.voiceSpeakBackOnHeadphones { self.speakBack(result.summary) }
        }
    }

    static func reviewCard(
        spec: LogSetSpec, transcript: String, entryIndex: Int, session: WorkoutSession,
        unit: WeightUnit
    ) -> ReviewCard {
        let first = spec.sets.first ?? LogSetSpec.SetValues()
        return ReviewCard(
            transcript: transcript, exerciseName: session.exercises[entryIndex].exercise.name,
            unit: unit, weightKg: first.weightKg, reps: first.reps,
            durationSeconds: first.durationSeconds, setCount: max(1, spec.sets.count),
            parsed: first, spec: spec, entryID: session.exercises[entryIndex].id
        )
    }
}
