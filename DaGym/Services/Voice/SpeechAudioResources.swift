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
///
/// **One `AVAudioEngine` per turn**, built in `start` and dropped in `tearDown`. An engine kept
/// across turns caches its `inputNode`'s hardware format; after a route change between two holds
/// (AirPods connecting, a car handing the phone back) the cached format no longer matches the
/// hardware, and the next `installTap`/`start` raises the uncatchable
/// `IsFormatSampleRateAndChannelCountValid` assertion. A fresh engine asks the hardware afresh.
final class SpeechAudioResources: @unchecked Sendable {
    private let lock = NSLock()
    /// Serialises `start` against `tearDownEngine`: the start runs on a detached task while a
    /// cancel from the main actor can tear down at any moment, and removing a tap while another
    /// thread is installing one on the same node is not something AVFAudio survives. Recursive
    /// because a failed start tears itself down.
    private let engineLock = NSRecursiveLock()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var observers: [NSObjectProtocol] = []
    private var isTapInstalled = false
    private var didEmit = false

    /// Why `start(request:)` refused to install the tap. `.formatNotReady` is the transient one
    /// (a Bluetooth route still negotiating its sample rate) that a caller may retry once.
    enum StartFailure: Error {
        case noInput
        case formatNotReady
        case engineStart
    }

    /// Starts a fresh engine with a tap feeding `request`.
    ///
    /// Every format is checked before the tap goes in, because `installTap(onBus:bufferSize:
    /// format:)` and `AVAudioEngine.start()` raise Objective-C exceptions — uncatchable hard
    /// crashes in Swift — for a 0 Hz or 0-channel format, and for a tap format that doesn't match
    /// the hardware's. Both are exactly what the input node reports when the route is mid-change,
    /// the mic is held by another app, or the session has no input at all. Failing here surfaces
    /// as a normal "voice logging hiccuped" alert (or a single retry) instead.
    func start(request: SFSpeechAudioBufferRecognitionRequest) throws(StartFailure) {
        engineLock.lock()
        defer { engineLock.unlock() }
        tearDownEngine()
        guard AVAudioSession.sharedInstance().isInputAvailable else { throw .noInput }

        let engine = AVAudioEngine()
        lock.withLock {
            self.engine = engine
            self.request = request
            didEmit = false
        }

        let inputNode = engine.inputNode
        let hardware = inputNode.inputFormat(forBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        guard Self.isUsable(hardware), Self.isUsable(format),
              hardware.sampleRate == format.sampleRate else {
            tearDownEngine()
            throw .formatNotReady
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
            throw .engineStart
        }
    }

    private static func isUsable(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    /// The engine this turn is running on, so `OnDeviceSpeechRecognizer` can scope its
    /// configuration-change observer to it and not to every engine in the process.
    var currentEngine: AVAudioEngine? {
        lock.withLock { engine }
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
        tearDownEngine()
        let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
            defer { self.request = nil }
            return self.request
        }
        request?.endAudio()
        VoiceAudioSession.deactivate()
    }

    /// Removes the tap, stops the engine and drops it. Idempotent; safe with no engine at all.
    private func tearDownEngine() {
        engineLock.lock()
        defer { engineLock.unlock() }
        let (engine, shouldRemoveTap) = lock.withLock { () -> (AVAudioEngine?, Bool) in
            defer {
                self.engine = nil
                isTapInstalled = false
            }
            return (self.engine, isTapInstalled)
        }
        guard let engine else { return }
        if shouldRemoveTap { engine.inputNode.removeTap(onBus: 0) }
        if engine.isRunning { engine.stop() }
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
