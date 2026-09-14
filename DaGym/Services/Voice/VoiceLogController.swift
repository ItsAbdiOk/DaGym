import Foundation
import GymCore

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
/// (auto-log, opt-in and off by default — see `VoiceAutoLogPolicy`) or hands it to the UI as a
/// reviewable card. Every mutation goes through `WorkoutSession.completeSet`/`addSet`
/// (`VoiceLogController+Apply.swift`) — the same calls `ActiveWorkoutView+Actions` makes for a tap
/// on the checkmark — so voice is never a parallel write path. Error classification lives in
/// `VoiceLogController+Errors.swift`, parse/validate in `VoiceLogController+Process.swift`.
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
        /// The user's display unit. Weights in this card are still canonical kg — this is what
        /// the view converts through, so an lb user is never shown (or asked to type) kg.
        var unit: WeightUnit
        var weightKg: Double?
        var reps: Int?
        var durationSeconds: Int?
        /// How many sets the utterance asked for ("three sets of eight at sixty" → 3). Shown on
        /// the card, and all of them are written on confirm.
        var setCount: Int
        /// The first set exactly as parsed, so confirm can tell an edited field from an
        /// untouched one and leave a heterogeneous spec ("10, 10, 8") alone.
        var parsed: LogSetSpec.SetValues
        var spec: LogSetSpec
        var entryID: UUID
    }

    enum VoiceLogError: Equatable {
        case permissionDenied
        /// Parental controls or an MDM profile blocks speech recognition — there is no Settings
        /// switch this user can flip, so the copy must not send them to one.
        case permissionRestricted
        case onDeviceUnavailable
        case nothingHeard
        case didNotUnderstand
        case exerciseNotInSession(spoken: String)
        case needsDisambiguation(spoken: String, candidates: [String])
        /// A grammar command v1's app layer doesn't act on yet (repeat/rate/correct/undo/
        /// swap/add/remove/rest/note/query) — parsed correctly, just not wired to a mutation.
        case unsupportedCommand
        /// The numbers on the review card don't pass `LogCommandValidator` (5000 kg, 0 reps).
        case valueOutOfRange
        case audioFailure
    }

    /// Read-only from outside `VoiceLogController*.swift` by convention (SwiftUI only ever binds
    /// to it); not `private(set)` because the other files in this feature also set it — the
    /// mutation still only ever happens from code in this feature, just split across files to
    /// stay under the line-count cap.
    var state: State = .idle
    let recognizer: any SpeechRecognizing
    let speaker: VoiceSpeechSynthesizing

    /// Whether audio was going to something worn when this turn's mic opened. Sampled while the
    /// recording session is live (see `stream()`), because that is the only time AVAudioSession
    /// lists a Bluetooth headset's microphone among `availableInputs` — the tie-breaker
    /// `VoiceSpeechSynthesizer.isRoutedToHeadphones` uses to tell AirPods from a gym speaker.
    /// Read at speak-back time, which happens after `stopListening()` has put the session back
    /// and that input has gone — asked live there, AirPods never qualified. Same file-split
    /// convention as `state`: set here, read from `VoiceLogController+Apply.swift`.
    var wornOutputAtListenStart = false

    private var listenTask: Task<Void, Never>?
    /// True between press and release. The permission prompts cancel the drag gesture holding
    /// the button, so this is how the listen task knows nobody is holding it any more.
    private var isHolding = false
    /// The recognizer's committed hypothesis for this turn, with its confidence. Nil until
    /// `.final` arrives — which is the whole point of waiting for it on release.
    private var finalTranscript: SpeechTranscript?
    private var streamEnded = false
    /// Bumped on every press. A release that was awaiting the final hypothesis when a *new*
    /// press arrived must not resume and tear that new turn down.
    private var turn = 0

    /// How long a release waits for the final hypothesis before giving up and using the last
    /// partial (which then can't auto-log, having no recognition confidence). The user is
    /// already done speaking, so this is dead time they feel — 0.8 s is the most we'll spend.
    private static let finalHypothesisTimeout = Duration.milliseconds(800)

    init(recognizer: any SpeechRecognizing, speaker: VoiceSpeechSynthesizing) {
        self.recognizer = recognizer
        self.speaker = speaker
    }

    // MARK: Hold-to-talk lifecycle

    /// Button press. Requests permission if needed, then starts streaming partial transcripts
    /// into `state`.
    func startHolding() {
        listenTask?.cancel()
        turn += 1
        isHolding = true
        finalTranscript = nil
        streamEnded = false
        state = .listening(partial: "")
        listenTask = Task { [weak self] in
            guard let self else { return }
            let authorization = recognizer.authorizationStatus == .notDetermined
                ? await recognizer.requestAuthorization()
                : recognizer.authorizationStatus
            // `.notDetermined` puts two system alerts under the held finger, which cancels the
            // drag gesture. Starting the mic now would leave "Listening…" up with nobody
            // holding anything — and the next release would log whatever the gym said.
            guard isHolding else {
                streamEnded = true
                state = .idle
                return
            }
            switch authorization {
            case .authorized:
                await stream()
            case .restricted:
                streamEnded = true
                state = .error(.permissionRestricted)
            default:
                streamEnded = true
                state = .error(.permissionDenied)
            }
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
        defer { streamEnded = true }
        do {
            let events = try recognizer.startListening()
            wornOutputAtListenStart = speaker.isRoutedToHeadphones
            for try await event in events {
                guard !Task.isCancelled else { return }
                switch event {
                case .partial(let text):
                    state = .listening(partial: text)
                case .final(let transcript):
                    finalTranscript = transcript
                    state = .listening(partial: transcript.text)
                }
            }
        } catch {
            // A cancelled turn's late failure must not overwrite what the release already
            // decided — the review card or auto-log toast is on screen by now.
            guard !Task.isCancelled else { return }
            state = .error(Self.failure(error))
        }
    }

    private static func failure(_ error: Error) -> VoiceLogError {
        switch error as? SpeechRecognitionFailure {
        case .onDeviceUnavailable: .onDeviceUnavailable
        case .notAuthorized: .permissionDenied
        case .noSpeechDetected: .nothingHeard
        default: .audioFailure
        }
    }

    /// Button release. Stops the mic, waits (briefly) for the recognizer's final hypothesis, and
    /// resolves it against the session — auto-logging or opening the review card.
    ///
    /// Async on purpose: parsing the partial transcript that happened to be in `state` when the
    /// finger lifted is how "eight reps at 225" released a beat early became "eight reps at 2",
    /// and 2.5 kg × 8 went into someone's history with no card and no undo prompt.
    func stopHolding(
        session: WorkoutSession, store: WorkoutStore, preferences: Preferences,
        undo: @escaping (UndoAction) -> Void
    ) async {
        guard isHolding else { return }
        isHolding = false
        let pressGeneration = turn

        recognizer.endAudio()
        await waitForFinalHypothesis()
        // A fresh press while we were waiting owns the recognizer now; this release belongs to a
        // turn that is over. Stopping it here would kill the new stream and log into the old one.
        guard pressGeneration == turn else { return }
        let transcript = (finalTranscript?.text ?? currentPartial)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = finalTranscript?.confidence
        recognizer.stopListening()
        listenTask?.cancel()
        listenTask = nil

        if let preserved = preservedError(transcript: transcript) {
            state = .error(preserved)
            return
        }
        let context = VoiceLogTurnContext(
            session: session, store: store, preferences: preferences, undo: undo
        )
        process(transcript: transcript, recognitionConfidence: confidence, turn: context)
    }

    /// Releasing the button mid-recognition (or navigating away) must tear down cleanly without
    /// touching the session — this is the "kill it mid-recognition" path, distinct from a normal
    /// release, which always calls `stopHolding(session:store:preferences:undo:)` instead. This
    /// is the only path that cancels the recognition task outright rather than letting the final
    /// hypothesis land.
    func cancel() {
        isHolding = false
        turn += 1
        recognizer.stopListening()
        listenTask?.cancel()
        listenTask = nil
        finalTranscript = nil
        state = .idle
    }

    func dismissReview() { state = .idle }

    private var currentPartial: String {
        if case .listening(let partial) = state { return partial }
        return ""
    }

    /// After `endAudio()` the recognizer still owes us a final hypothesis. Polling rather than a
    /// continuation on purpose: the final can arrive before, during or after this call, and the
    /// stream can also simply end — one loop covers all three with no resume-twice hazard, at a
    /// cost of at most 40 main-actor wake-ups.
    private func waitForFinalHypothesis() async {
        let deadline = ContinuousClock.now + Self.finalHypothesisTimeout
        while finalTranscript == nil, !streamEnded, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// An error raised while the finger was still down is the real answer for this turn. Release
    /// used to see "not `.listening`, empty transcript" and overwrite every one of them with
    /// "Didn't catch that" — so a user who had just denied microphone access was told to speak
    /// louder instead of being sent to Settings.
    private func preservedError(transcript: String) -> VoiceLogError? {
        guard case .error(let existing) = state else { return nil }
        switch existing {
        case .permissionDenied, .permissionRestricted, .onDeviceUnavailable, .audioFailure:
            return existing
        default:
            return transcript.isEmpty ? existing : nil
        }
    }
}
