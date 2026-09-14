import Foundation
import GymCore

/// Auto-log confidence gate. `minConfidence` is deliberately high (well above
/// `ExerciseMatcher.threshold`'s 0.82) because auto-logging silently mutates the workout — unlike
/// a normal confirm-card flow, there's no "are you sure" between the parse and the write. 0.90
/// only lets through utterances the closed grammar matched cleanly (an exact single-set pattern,
/// no ambiguity, no out-of-range numbers) rather than anything that merely cleared the exercise
/// matcher's own, looser bar. Combined with "zero validation flags" and "single set only" (see
/// `VoiceLogController.isEligible`), this keeps auto-log to the exact case the spec asks for —
/// "two twenty-five for eight" — while anything even slightly uncertain (a fuzzy exercise name, a
/// suspicious jump, multiple sets) always lands on the review card instead.
enum VoiceAutoLogPolicy {
    static let minConfidence = 0.90
}

/// One set's before/after, so an auto-logged (or manually confirmed) command can be undone
/// exactly — including un-inserting a set this command had to add because every planned set was
/// already done. See `VoiceLogController+Apply.swift`.
struct VoiceLogSetSnapshot {
    var entryID: UUID
    var setID: UUID
    var previous: SetEntry
    var wasInserted: Bool
}

/// The session/store/preferences/undo quadruple every step of one hold-to-talk turn needs to
/// pass along — bundled so `handle(validated:confidence:transcript:turn:)` and
/// `handleLogSet(_:flags:confidence:transcript:turn:)` stay under the parameter-count cap.
struct VoiceLogTurnContext {
    var session: WorkoutSession
    var store: WorkoutStore
    var preferences: Preferences
    var undo: (UndoAction) -> Void
}

/// Orchestrates one hold-to-talk turn: builds a `GymCore.ParseContext` from the live
/// `WorkoutSession` (`VoiceLogController+Context.swift`), runs the transcript through
/// `VoiceCommandParser`/`LogCommandValidator`, and either applies the result immediately
/// (auto-log) or hands it to the UI as a reviewable card. Every mutation goes through
/// `WorkoutSession.completeSet`/`addSet` (`VoiceLogController+Apply.swift`) — the same calls
/// `ActiveWorkoutView+Actions` makes for a tap on the checkmark — so voice is never a parallel
/// write path. Error classification lives in `VoiceLogController+Errors.swift`.
@MainActor
@Observable
final class VoiceLogController {
    enum State: Equatable {
        case idle
        case listening(partial: String)
        case reviewing(ReviewCard)
        case autoLogged(message: String)
        case error(VoiceLogError)
    }

    /// The "what I understood" card: editable fields the user can confirm or adjust before
    /// logging, for anything that didn't clear the auto-log bar.
    struct ReviewCard: Equatable, Identifiable {
        let id = UUID()
        var transcript: String
        var exerciseName: String
        var weightKg: Double?
        var reps: Int?
        var durationSeconds: Int?
        var spec: LogSetSpec
        var entryID: UUID
    }

    enum VoiceLogError: Equatable {
        case permissionDenied
        case onDeviceUnavailable
        case nothingHeard
        case didNotUnderstand
        case exerciseNotInSession(spoken: String)
        case needsDisambiguation(spoken: String, candidates: [String])
        /// A grammar command v1's app layer doesn't act on yet (repeat/rate/correct/undo/
        /// swap/add/remove/rest/note/query) — parsed correctly, just not wired to a mutation.
        case unsupportedCommand
        case audioFailure
    }

    /// Read-only from outside `VoiceLogController*.swift` by convention (SwiftUI only ever binds
    /// to it); not `private(set)` because `VoiceLogController+Apply.swift` also sets it — the
    /// mutation still only ever happens from code in this feature, just split across files to
    /// stay under the line-count cap.
    var state: State = .idle
    let recognizer: any SpeechRecognizing
    let speaker: VoiceSpeechSynthesizing
    private var listenTask: Task<Void, Never>?

    init(recognizer: any SpeechRecognizing, speaker: VoiceSpeechSynthesizing) {
        self.recognizer = recognizer
        self.speaker = speaker
    }

    // MARK: Hold-to-talk lifecycle

    /// Button press. Requests permission if needed, then starts streaming partial transcripts
    /// into `state`.
    func startHolding() {
        listenTask?.cancel()
        state = .listening(partial: "")
        listenTask = Task {
            let authorization = recognizer.authorizationStatus == .notDetermined
                ? await recognizer.requestAuthorization()
                : recognizer.authorizationStatus
            guard authorization == .authorized else {
                state = .error(.permissionDenied)
                return
            }
            await stream()
        }
    }

    /// Test seam: awaits the listen loop `startHolding()` kicked off, so a test driving a
    /// scripted `SpeechRecognizing` can be sure every event landed in `state` before calling
    /// `stopHolding(...)`. The real UI never needs this — button release always comes after the
    /// user has already seen (and stopped producing) partial transcripts.
    func waitForListening() async {
        await listenTask?.value
    }

    private func stream() async {
        do {
            let events = try recognizer.startListening()
            for try await event in events {
                guard !Task.isCancelled else { return }
                switch event {
                case .partial(let text): state = .listening(partial: text)
                case .final(let text): state = .listening(partial: text)
                }
            }
        } catch SpeechRecognitionFailure.onDeviceUnavailable {
            state = .error(.onDeviceUnavailable)
        } catch SpeechRecognitionFailure.notAuthorized {
            state = .error(.permissionDenied)
        } catch SpeechRecognitionFailure.noSpeechDetected {
            state = .error(.nothingHeard)
        } catch {
            state = .error(.audioFailure)
        }
    }

    /// Button release. Tears down the recognizer, takes whatever transcript it had, and resolves
    /// it against the session — auto-logging or opening the review card.
    func stopHolding(
        session: WorkoutSession, store: WorkoutStore, preferences: Preferences,
        undo: @escaping (UndoAction) -> Void
    ) {
        let transcript: String
        if case .listening(let partial) = state { transcript = partial } else { transcript = "" }
        recognizer.stopListening()
        listenTask?.cancel()
        listenTask = nil
        process(transcript: transcript, session: session, store: store, preferences: preferences, undo: undo)
    }

    /// Releasing the button mid-recognition (or navigating away) must tear down cleanly without
    /// touching the session — this is the "kill it mid-recognition" path, distinct from a normal
    /// release, which always calls `stopHolding(session:store:preferences:undo:)` instead.
    func cancel() {
        recognizer.stopListening()
        listenTask?.cancel()
        listenTask = nil
        state = .idle
    }

    func dismissReview() { state = .idle }

    // MARK: Parsing → validation → application

    private func process(
        transcript: String, session: WorkoutSession, store: WorkoutStore, preferences: Preferences,
        undo: @escaping (UndoAction) -> Void
    ) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .error(.nothingHeard); return }

        let context = Self.buildContext(session: session, preferences: preferences)
        let result = VoiceCommandParser.parse(trimmed, context: context)
        guard !result.commands.isEmpty else { state = .error(.didNotUnderstand); return }

        if let notInSession = Self.unresolvedExerciseNotInSession(result.commands) {
            state = .error(notInSession)
            return
        }

        switch LogCommandValidator.validate(result.commands, in: context, hasUndoReceipt: false) {
        case .failure(let error):
            state = .error(Self.map(error, commands: result.commands))
        case .success(let validated):
            let turn = VoiceLogTurnContext(
                session: session, store: store, preferences: preferences, undo: undo
            )
            handle(validated: validated, confidence: result.confidence, transcript: trimmed, turn: turn)
        }
    }

    private func handle(
        validated: [ValidatedCommand], confidence: Double, transcript: String, turn: VoiceLogTurnContext
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
            if Self.isEligible(confidence: confidence, flags: only.flags) {
                applyCompleteOnDeck(
                    session: turn.session, store: turn.store, preferences: turn.preferences, undo: turn.undo
                )
            } else {
                state = .error(.unsupportedCommand)
            }
        default:
            // Repeat/rate/correct/undo/swap/add/remove/rest/note/query: parsed correctly by
            // GymCore, but v1's app layer only ever writes a logSet/completeOnDeck — see
            // `VoiceLogError.unsupportedCommand`.
            state = .error(.unsupportedCommand)
        }
    }

    private func handleLogSet(
        _ spec: LogSetSpec, flags: [ValidationFlag], confidence: Double, transcript: String,
        turn: VoiceLogTurnContext
    ) {
        let session = turn.session
        let store = turn.store
        let preferences = turn.preferences
        let undo = turn.undo
        guard let entryIndex = Self.resolveEntryIndex(exercise: spec.exercise, session: session) else {
            state = .error(.unsupportedCommand)
            return
        }
        let exerciseName = session.exercises[entryIndex].exercise.name

        if spec.sets.count == 1, Self.isEligible(confidence: confidence, flags: flags) {
            apply(spec: spec, entryIndex: entryIndex, session: session, store: store) { result in
                undo(UndoAction(message: result.summary, undo: result.undo))
                self.state = .autoLogged(message: result.summary)
                if preferences.voiceSpeakBackOnHeadphones { self.speakBack(result.summary) }
            }
            return
        }

        state = .reviewing(ReviewCard(
            transcript: transcript, exerciseName: exerciseName,
            weightKg: spec.sets.first?.weightKg, reps: spec.sets.first?.reps,
            durationSeconds: spec.sets.first?.durationSeconds, spec: spec,
            entryID: session.exercises[entryIndex].id
        ))
    }

    /// The review card's "Log" button — applies exactly what's shown (or was edited into) the
    /// card, through the same mutation path as an auto-log.
    func confirmReview(
        _ card: ReviewCard, session: WorkoutSession, store: WorkoutStore, undo: @escaping (UndoAction) -> Void
    ) {
        guard let entryIndex = session.exercises.firstIndex(where: { $0.id == card.entryID }) else {
            state = .error(.unsupportedCommand)
            return
        }
        var spec = card.spec
        spec.sets = [LogSetSpec.SetValues(
            reps: card.reps, weightKg: card.weightKg, durationSeconds: card.durationSeconds,
            assistanceKg: spec.sets.first?.assistanceKg, addedKg: spec.sets.first?.addedKg,
            isBodyweight: spec.sets.first?.isBodyweight ?? false
        )]
        apply(spec: spec, entryIndex: entryIndex, session: session, store: store) { result in
            undo(UndoAction(message: result.summary, undo: result.undo))
            self.state = .idle
        }
    }
}
