import Foundation

@testable import DaGym

/// A scripted `SpeechRecognizing` — no audio hardware, no `Speech` framework. Configure
/// `authorizationStatus`/`scriptedEvents`/`startError` before calling `startHolding()`.
///
/// By default the stream finishes right after yielding `scriptedEvents` (the common case: a
/// clean hold-then-release). Set `finishesAutomatically = false` to model a still-listening
/// recognizer that only ends when `endAudio()`/`stopListening()` is called — the shape needed to
/// test "released mid-recognition", and the shape needed to model the real thing's timing, where
/// the *final* hypothesis only arrives after the audio stops. `finalAfterEndAudio` is that final:
/// set it alongside a truncated `.partial` to reproduce "eight reps at 2" on screen resolving to
/// "eight reps at 225" a beat later.
@MainActor
final class FakeSpeechRecognizer: SpeechRecognizing {
    var authorizationStatus: VoiceAuthorizationStatus
    /// Returned by `requestAuthorization()` — separate from `authorizationStatus` so a test can
    /// assert the "before" state was `.notDetermined` and the "after" state came from the prompt.
    var authorizationToGrant: VoiceAuthorizationStatus
    /// Events yielded by the stream `startListening()` returns, in order.
    var scriptedEvents: [SpeechRecognitionEvent] = []
    /// Yielded as `.final` when `endAudio()` is called, the way a real recognizer commits to a
    /// hypothesis only once the audio stops.
    var finalAfterEndAudio: SpeechTranscript?
    /// Thrown synchronously from `startListening()` instead of returning a stream, when set.
    var startError: SpeechRecognitionFailure?
    var finishesAutomatically = true
    /// `endAudio()` ends the stream (the default) so tests that script no final don't pay the
    /// controller's real 0.8 s wait. Set `false` to model a recognizer that is still deciding —
    /// which is the window a second press has to land in to reproduce the re-press race.
    var finishesOnEndAudio = true
    /// How long `requestAuthorization()` suspends before answering — the system permission
    /// sheet, during which the gesture holding the button is cancelled and a release arrives.
    var authorizationDelay: Duration?
    /// How long `startListening()` suspends before returning its stream — the real recogniser's
    /// wait for a Bluetooth route to settle.
    var startDelay: Duration?

    private(set) var startListeningCallCount = 0
    private(set) var endAudioCallCount = 0
    private(set) var stopListeningCallCount = 0
    private var continuation: AsyncThrowingStream<SpeechRecognitionEvent, Error>.Continuation?

    init(
        authorizationStatus: VoiceAuthorizationStatus = .authorized,
        authorizationToGrant: VoiceAuthorizationStatus? = nil
    ) {
        self.authorizationStatus = authorizationStatus
        self.authorizationToGrant = authorizationToGrant ?? authorizationStatus
    }

    func requestAuthorization() async -> VoiceAuthorizationStatus {
        if let authorizationDelay { try? await Task.sleep(for: authorizationDelay) }
        authorizationStatus = authorizationToGrant
        return authorizationStatus
    }

    func startListening() async throws -> AsyncThrowingStream<SpeechRecognitionEvent, Error> {
        startListeningCallCount += 1
        if let startError { throw startError }
        if let startDelay { try? await Task.sleep(for: startDelay) }
        let (stream, continuation) = AsyncThrowingStream<SpeechRecognitionEvent, Error>.makeStream()
        self.continuation = continuation
        for event in scriptedEvents { continuation.yield(event) }
        if finishesAutomatically {
            continuation.finish()
            self.continuation = nil
        }
        return stream
    }

    func endAudio() {
        endAudioCallCount += 1
        guard let continuation else { return }
        if let finalAfterEndAudio { continuation.yield(.final(finalAfterEndAudio)) }
        guard finishesOnEndAudio else { return }
        continuation.finish()
        self.continuation = nil
    }

    func stopListening() {
        stopListeningCallCount += 1
        continuation?.finish()
        continuation = nil
    }
}

/// A no-op `VoiceSpeechSynthesizing` that records what it was asked to say.
@MainActor
final class FakeVoiceSpeechSynthesizer: VoiceSpeechSynthesizing {
    var isRoutedToHeadphones = false
    private(set) var spoken: [String] = []

    func speak(_ text: String) {
        spoken.append(text)
    }
}
