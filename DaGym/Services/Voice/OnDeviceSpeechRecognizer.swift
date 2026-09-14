import AVFAudio
import Foundation
import Speech

/// The real `SpeechRecognizing`: `SFSpeechRecognizer` in on-device-only mode over an
/// `AVAudioEngine` tap. Never sends audio to a server — see `requiresOnDeviceRecognition` below —
/// and if on-device recognition isn't available for this locale/device, this fails with
/// `.onDeviceUnavailable` rather than silently falling back to the network.
///
/// Concurrency: this class is `@MainActor`; every piece of state Apple's callbacks touch lives
/// either in `resources` (lock-guarded, `Sendable`) or in the `AsyncThrowingStream.Continuation`
/// captured directly by the result handler. The handler deliberately does **not** hop to the main
/// actor to deliver events: a `Task { @MainActor in … }` per callback reorders partials and lets
/// a cancelled task's late error finish a *newer* stream. `Continuation` is safe to call from any
/// thread, so events are yielded inline and only teardown hops back — guarded by `generation` so
/// a stale task can never tear down a live one.
@MainActor
final class OnDeviceSpeechRecognizer: SpeechRecognizing {
    private let recognizer: SFSpeechRecognizer?
    private let resources = SpeechAudioResources()
    private var continuation: AsyncThrowingStream<SpeechRecognitionEvent, Error>.Continuation?
    /// Bumped on every start and stop. A recognition callback carries the generation it was
    /// created in and is ignored once that generation is over.
    private var generation = 0

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    deinit {
        // A view dropped mid-hold (or an app teardown) must not leave the mic open, the engine
        // running and the user's music ducked. `resources` is `Sendable` and self-locking, so
        // this is legal from a nonisolated `deinit`.
        resources.tearDown()
    }

    var authorizationStatus: VoiceAuthorizationStatus { VoiceAuthorization.currentStatus() }

    func requestAuthorization() async -> VoiceAuthorizationStatus {
        await VoiceAuthorization.request()
    }

    func startListening() throws -> AsyncThrowingStream<SpeechRecognitionEvent, Error> {
        stopListening() // Clean slate: never stack a second tap/task on top of a live one.

        guard authorizationStatus == .authorized else { throw SpeechRecognitionFailure.notAuthorized }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw SpeechRecognitionFailure.onDeviceUnavailable
        }

        do {
            try VoiceAudioSession.activateForRecording()
        } catch {
            throw SpeechRecognitionFailure.audioEngineUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        do {
            try resources.start(request: request)
        } catch {
            VoiceAudioSession.deactivate()
            throw SpeechRecognitionFailure.audioEngineUnavailable
        }

        generation += 1
        let generation = self.generation
        let (stream, continuation) = AsyncThrowingStream<SpeechRecognitionEvent, Error>.makeStream()
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stopListening(ifGeneration: generation) }
        }

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Self.handle(
                result: result, error: error, continuation: continuation,
                resources: self?.resources
            ) {
                Task { @MainActor in self?.stopListening(ifGeneration: generation) }
            }
        }
        resources.adopt(task: task)
        observeRouteAndInterruptions(generation: generation)
        return stream
    }

    /// Yields one recognition callback onto `continuation` and reports whether the turn is over.
    /// `static` on purpose: it runs on Apple's callback thread and must touch no isolated state.
    nonisolated private static func handle(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        continuation: AsyncThrowingStream<SpeechRecognitionEvent, Error>.Continuation,
        resources: SpeechAudioResources?,
        finished: @Sendable () -> Void
    ) {
        if let error {
            // A failed recognition — including the routine "no speech detected" — used to leave
            // the tap, engine and audio session live with the user's music still ducked.
            continuation.finish(throwing: error)
            finished()
            return
        }
        guard let result else { return }
        let text = result.bestTranscription.formattedString
        guard !text.isEmpty else { return }
        resources?.markEmitted()
        guard result.isFinal else {
            continuation.yield(.partial(text))
            return
        }
        continuation.yield(
            .final(SpeechTranscript(text, confidence: confidence(of: result.bestTranscription)))
        )
        continuation.finish()
        finished()
    }

    /// The recognizer's own certainty about the words it returned: the mean of
    /// `SFTranscriptionSegment.confidence` across the final hypothesis's segments. Apple reports
    /// 0 for every segment of a non-final result, and for some locales/devices even on a final
    /// one — `SpeechTranscript.confidence` documents that 0 means *unknown*, and
    /// `VoiceAutoLogPolicy` refuses to auto-log on an unknown.
    nonisolated private static func confidence(of transcription: SFTranscription) -> Double {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0 }
        let total = segments.reduce(0.0) { $0 + Double($1.confidence) }
        return max(0, min(1, total / Double(segments.count)))
    }

    func endAudio() {
        resources.endAudio()
    }

    func stopListening() {
        stopListening(ifGeneration: nil)
    }

    /// `generation` scopes a teardown to the turn that asked for it, so a late callback from a
    /// cancelled task can't stop the engine a fresh press just started.
    private func stopListening(ifGeneration generation: Int?) {
        if let generation, generation != self.generation { return }
        self.generation += 1
        let hadTranscript = resources.hasEmitted
        resources.tearDown()
        guard let continuation else { return }
        self.continuation = nil
        if hadTranscript {
            continuation.finish()
        } else {
            continuation.finish(throwing: SpeechRecognitionFailure.noSpeechDetected)
        }
    }

    /// AirPods (or any output) disconnecting mid-hold, and a phone call or other interruption,
    /// both end listening cleanly instead of talking to a dead or pre-empted route.
    private func observeRouteAndInterruptions(generation: Int) {
        let center = NotificationCenter.default
        let route = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                  reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.stopListening(ifGeneration: generation) }
        }
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                  type == .began else { return }
            Task { @MainActor in self?.stopListening(ifGeneration: generation) }
        }
        resources.adopt(observer: route)
        resources.adopt(observer: interruption)
    }
}
