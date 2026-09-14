import Foundation

@testable import DaGym

/// A scripted `SpeechRecognizing` — no audio hardware, no `Speech` framework. Configure
/// `authorizationStatus`/`scriptedEvents`/`startError` before calling `startHolding()`.
///
/// By default the stream finishes right after yielding `scriptedEvents` (the common case: a
/// clean hold-then-release). Set `finishesAutomatically = false` to model a still-listening
/// recognizer that only ends when `stopListening()` is called — the shape needed to test
/// "released mid-recognition" without a real, indefinitely-suspending audio stream.
@MainActor
final class FakeSpeechRecognizer: SpeechRecognizing {
    var authorizationStatus: VoiceAuthorizationStatus
    /// Returned by `requestAuthorization()` — separate from `authorizationStatus` so a test can
    /// assert the "before" state was `.notDetermined` and the "after" state came from the prompt.
    var authorizationToGrant: VoiceAuthorizationStatus
    /// Events yielded by the stream `startListening()` returns, in order.
    var scriptedEvents: [SpeechRecognitionEvent] = []
    /// Thrown synchronously from `startListening()` instead of returning a stream, when set.
    var startError: SpeechRecognitionFailure?
    var finishesAutomatically = true

    private(set) var startListeningCallCount = 0
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
        authorizationStatus = authorizationToGrant
        return authorizationStatus
    }

    func startListening() throws -> AsyncThrowingStream<SpeechRecognitionEvent, Error> {
        startListeningCallCount += 1
        if let startError { throw startError }
        let (stream, continuation) = AsyncThrowingStream<SpeechRecognitionEvent, Error>.makeStream()
        self.continuation = continuation
        for event in scriptedEvents { continuation.yield(event) }
        if finishesAutomatically {
            continuation.finish()
            self.continuation = nil
        }
        return stream
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
