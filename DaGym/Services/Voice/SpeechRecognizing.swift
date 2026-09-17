import Foundation

/// A recognized utterance plus how sure the *recognizer* is that those are the words that were
/// said. `confidence` is the mean `SFTranscriptionSegment.confidence` over the segments of the
/// final hypothesis, 0…1.
///
/// `0` means **unknown**, not "certainly wrong": Apple only populates segment confidence on a
/// final result, so every partial carries 0, and some locales/devices report 0 even on a final.
/// `VoiceAutoLogPolicy` treats unknown as "not eligible for auto-log" rather than as a low score —
/// silently writing to someone's training log needs a number we actually have.
struct SpeechTranscript: Sendable, Equatable {
    var text: String
    var confidence: Double

    init(_ text: String, confidence: Double = 0) {
        self.text = text
        self.confidence = confidence
    }
}

/// One update from an in-progress recognition. `.partial` fires repeatedly as the recognizer
/// refines its guess and carries no confidence; `.final` fires once, when the recognizer has
/// committed to a hypothesis — which, after `endAudio()`, is the transcript the app acts on.
enum SpeechRecognitionEvent: Sendable, Equatable {
    case partial(String)
    case final(SpeechTranscript)
}

/// Failures `SpeechRecognizing` can throw or finish a stream with. Each maps to one of the
/// specific, actionable error states `VoiceLogController` surfaces (see plan §2).
enum SpeechRecognitionFailure: Error, Sendable, Equatable {
    /// Speech and/or microphone permission isn't granted. Callers should check
    /// `authorizationStatus`/`requestAuthorization()` first; this is the "asked anyway" case.
    case notAuthorized
    /// On-device recognition isn't available for this locale/device right now. Per the app's
    /// no-network promise, this never falls back to server-based recognition — it fails instead.
    case onDeviceUnavailable
    /// The audio engine couldn't start (route conflict, hardware busy, an input format the tap
    /// can't be installed with).
    case audioEngineUnavailable
    /// The recognizer ended without ever producing a transcript.
    case noSpeechDetected
}

/// The seam between the voice-logging UI and Apple's speech APIs, so `VoiceLogController` can be
/// tested with a fake instead of real audio hardware. The one real implementation is
/// `OnDeviceSpeechRecognizer`.
///
/// On-device only: DaGym's privacy policy promises audio never leaves the device, so
/// `requiresOnDeviceRecognition` is always `true` in the real implementation and there is no
/// network fallback — `.onDeviceUnavailable` is a terminal failure, not a prompt to go online.
@MainActor
protocol SpeechRecognizing: AnyObject {
    /// The current combined speech + microphone permission state, without prompting.
    var authorizationStatus: VoiceAuthorizationStatus { get }

    /// Prompts for speech recognition, then (only if that's granted) microphone access.
    func requestAuthorization() async -> VoiceAuthorizationStatus

    /// Starts capturing audio and recognizing speech, returning a stream of transcript updates.
    /// The stream finishes (with an error, if any) when `stopListening()` is called, the
    /// recognizer ends on its own, or the route is lost (e.g. AirPods disconnect mid-hold).
    /// Throws if listening can't start at all (no permission, no on-device support, audio
    /// engine busy) rather than opening a stream that immediately fails. Async because the real
    /// implementation may wait a beat for a Bluetooth route to settle before installing its tap.
    func startListening() async throws -> AsyncThrowingStream<SpeechRecognitionEvent, Error>

    /// Stops feeding audio to the recognizer but **leaves the recognition task alive** so its
    /// final hypothesis can still arrive. This is what a button *release* calls first: the last
    /// partial is routinely a truncated guess ("eight reps at 2" for "…at 225"), so acting on it
    /// is how wrong numbers get written to a training log. Callers then wait a bounded time for
    /// `.final` and call `stopListening()` afterwards, whatever arrived.
    func endAudio()

    /// Ends the audio engine and recognition task and releases the input tap. Safe to call at
    /// any time, including when nothing is listening — this is what an explicit cancel calls, so
    /// it must never leak a tap or leave the audio session stuck active.
    func stopListening()
}
