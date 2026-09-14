import Foundation

/// One update from an in-progress recognition. `.partial` fires repeatedly as the recognizer
/// refines its guess; `.final` fires once if the recognizer becomes confident enough to end on
/// its own (v1's hold-to-talk button always ends the session itself on release, but the seam
/// supports a recognizer that finishes early).
enum SpeechRecognitionEvent: Sendable, Equatable {
    case partial(String)
    case final(String)
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
    /// The audio engine couldn't start (route conflict, hardware busy, etc.).
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
    /// Throws synchronously if listening can't start at all (no permission, no on-device
    /// support, audio engine busy) rather than opening a stream that immediately fails.
    func startListening() throws -> AsyncThrowingStream<SpeechRecognitionEvent, Error>

    /// Ends the audio engine and recognition task and releases the input tap. Safe to call at
    /// any time, including when nothing is listening — this is what a button release always
    /// calls, so it must never leak a tap or leave the audio session stuck active.
    func stopListening()
}
