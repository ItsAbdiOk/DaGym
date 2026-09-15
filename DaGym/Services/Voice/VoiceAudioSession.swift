import AVFAudio
import Synchronization

/// Configures the shared `AVAudioSession` for on-device speech capture without stopping the
/// user's music any more than necessary, and restores it afterwards.
///
/// There is exactly one `AVAudioSession` per process, and DaGym has two would-be owners: this
/// (a live `AVAudioEngine` input tap) and `RestAlertPlayer`'s bleep. Changing the category out
/// from under a running engine stops that engine while the tap stays installed — the partial
/// transcript freezes and the release logs a truncated number. So this type is the coordinator:
/// `isRecordingActive` is the flag `RestAlertPlayer` checks before touching the category, and
/// nothing else in the app may call `setCategory` while it's true.
///
/// Deliberately not `@MainActor`: `OnDeviceSpeechRecognizer.deinit` and the audio-route
/// notification both need to deactivate from a nonisolated context. The state is a `Mutex`
/// instead.
enum VoiceAudioSession {
    /// The category/mode/options in force before the first `activateForRecording()`, kept as raw
    /// values so the stored state stays trivially `Sendable`.
    private struct Saved: Sendable {
        var category: String
        var mode: String
        var options: UInt
    }

    private struct State: Sendable {
        var saved: Saved?
        var isRecordingActive = false
    }

    private static let state = Mutex(State())

    /// True between `activateForRecording()` and `deactivate()`. `RestAlertPlayer` must leave the
    /// audio session alone while this is set.
    static var isRecordingActive: Bool {
        state.withLock { $0.isRecordingActive }
    }

    /// `.playAndRecord` so recording doesn't kill playback outright, `.duckOthers` so music
    /// quiets down for the hold instead of stopping, and Bluetooth options so AirPods (already
    /// connected for the workout) are used for both playback and the mic rather than falling
    /// back to the phone's speaker/mic mid-route.
    static func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        state.withLock { state in
            if state.saved == nil {
                state.saved = Saved(
                    category: session.category.rawValue, mode: session.mode.rawValue,
                    options: session.categoryOptions.rawValue
                )
            }
        }
        do {
            try session.setCategory(
                .playAndRecord, mode: .measurement,
                options: [.duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state.withLock { $0.isRecordingActive = false }
            throw error
        }
        state.withLock { $0.isRecordingActive = true }
    }

    /// Lets whatever was ducked come back up **and puts the category back the way we found it** —
    /// leaving `.playAndRecord + .defaultToSpeaker + .duckOthers` in place would keep routing
    /// every later sound (the rest bleep included) through the recording configuration. Errors
    /// are swallowed: deactivating is always best-effort cleanup, never something a caller should
    /// have to handle. Idempotent, so the release path, the route observer and `deinit` can all
    /// call it. A no-op when nothing was ever activated: `setActive(false)` on a session this
    /// type never touched still deactivates it — which, from a discarded recognizer's `deinit`
    /// mid-rest, cut off the rest bleep and the user's music for nothing.
    static func deactivate() {
        let saved: Saved? = state.withLock { state in
            guard state.isRecordingActive || state.saved != nil else { return nil }
            state.isRecordingActive = false
            defer { state.saved = nil }
            return state.saved
        }
        guard let saved else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(
            AVAudioSession.Category(rawValue: saved.category),
            mode: AVAudioSession.Mode(rawValue: saved.mode),
            options: AVAudioSession.CategoryOptions(rawValue: saved.options)
        )
    }
}
