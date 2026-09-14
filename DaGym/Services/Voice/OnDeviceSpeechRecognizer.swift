import AVFAudio
import Foundation
import Speech

/// The real `SpeechRecognizing`: `SFSpeechRecognizer` in on-device-only mode over an
/// `AVAudioEngine` tap. Never sends audio to a server — see `requiresOnDeviceRecognition` below —
/// and if on-device recognition isn't available for this locale/device, this fails with
/// `.onDeviceUnavailable` rather than silently falling back to the network.
///
/// Concurrency: this class is `@MainActor`, so its own state (`audioEngine`, `request`, `task`,
/// `continuation`) is only ever touched from the main actor. The two places Apple calls back on
/// an unspecified thread — the audio tap block and the recognition task's result handler — never
/// touch that state directly. The tap block only calls `request.append(_:)`, which Apple
/// documents as safe to call from any thread; the result handler extracts plain `Sendable` values
/// (`String?`, `Bool`, `Error?`) and hops to the main actor with `Task { @MainActor in }` before
/// touching anything isolated.
@MainActor
final class OnDeviceSpeechRecognizer: SpeechRecognizing {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncThrowingStream<SpeechRecognitionEvent, Error>.Continuation?
    private var routeObserver: NSObjectProtocol?
    private var didEmitAnything = false

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
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
        self.request = request
        didEmitAnything = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.request = nil
            VoiceAudioSession.deactivate()
            throw SpeechRecognitionFailure.audioEngineUnavailable
        }

        let (stream, continuation) = AsyncThrowingStream<SpeechRecognitionEvent, Error>.makeStream()
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stopListening() }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                self?.handle(text: text, isFinal: isFinal, error: error)
            }
        }

        observeRouteChanges()
        return stream
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        VoiceAudioSession.deactivate()
        if let continuation {
            self.continuation = nil
            if !didEmitAnything {
                continuation.finish(throwing: SpeechRecognitionFailure.noSpeechDetected)
            } else {
                continuation.finish()
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, error: Error?) {
        guard let continuation else { return }
        if let error {
            self.continuation = nil
            continuation.finish(throwing: error)
            return
        }
        guard let text, !text.isEmpty else { return }
        didEmitAnything = true
        continuation.yield(isFinal ? .final(text) : .partial(text))
        if isFinal {
            self.continuation = nil
            continuation.finish()
        }
    }

    /// AirPods (or any output) disconnecting mid-hold ends listening cleanly instead of talking
    /// to a dead route.
    private func observeRouteChanges() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                  reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.stopListening() }
        }
    }
}
