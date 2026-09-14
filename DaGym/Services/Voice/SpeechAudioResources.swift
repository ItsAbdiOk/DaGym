import AVFAudio
import Foundation
import Speech

/// The audio-engine, recognition-task and notification-observer handles for one listening turn,
/// held together so they can be released from anywhere — including `deinit` and an audio-session
/// interruption, neither of which can hop to the main actor first. `OnDeviceSpeechRecognizer` is
/// `@MainActor` and owns one of these as a `let`; all mutable state lives behind the lock here.
///
/// Leaving any of this running is not a leak in the abstract: the tap holds the microphone, the
/// engine holds the audio session, and `.duckOthers` keeps the user's music quiet until it's
/// handed back.
final class SpeechAudioResources: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var observers: [NSObjectProtocol] = []
    private var isTapInstalled = false
    private var didEmit = false

    /// Starts the engine with a tap feeding `request`.
    ///
    /// The input format is checked first: `installTap(onBus:bufferSize:format:)` raises an
    /// Objective-C exception — an uncatchable hard crash in Swift — for a 0 Hz or 0-channel
    /// format, which is exactly what `inputNode.outputFormat(forBus: 0)` returns when the route
    /// is mid-change or the mic is held by another app. Failing here surfaces as a normal
    /// "voice logging hiccuped" alert instead.
    func start(request: SFSpeechAudioBufferRecognitionRequest) throws {
        lock.lock()
        self.request = request
        didEmit = false
        lock.unlock()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechRecognitionFailure.audioEngineUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        lock.withLock { isTapInstalled = true }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            tearDown()
            throw SpeechRecognitionFailure.audioEngineUnavailable
        }
    }

    func adopt(task: SFSpeechRecognitionTask) {
        lock.withLock { self.task = task }
    }

    func adopt(observer: NSObjectProtocol) {
        lock.withLock { observers.append(observer) }
    }

    func markEmitted() {
        lock.withLock { didEmit = true }
    }

    var hasEmitted: Bool {
        lock.withLock { didEmit }
    }

    /// Stops sending audio but leaves the recognition task alive, so the final hypothesis can
    /// still land. The mic and the audio session are released here — only the (now silent)
    /// recognition task remains.
    func endAudio() {
        let shouldRemoveTap = lock.withLock { () -> Bool in
            let installed = isTapInstalled
            isTapInstalled = false
            return installed
        }
        if shouldRemoveTap { engine.inputNode.removeTap(onBus: 0) }
        if engine.isRunning { engine.stop() }
        let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
            defer { self.request = nil }
            return self.request
        }
        request?.endAudio()
        VoiceAudioSession.deactivate()
    }

    /// Everything `endAudio()` does, plus cancelling the recognition task and dropping the
    /// notification observers. Idempotent.
    func tearDown() {
        endAudio()
        let (task, observers) = lock.withLock { () -> (SFSpeechRecognitionTask?, [NSObjectProtocol]) in
            defer {
                self.task = nil
                self.observers = []
            }
            return (self.task, self.observers)
        }
        task?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
