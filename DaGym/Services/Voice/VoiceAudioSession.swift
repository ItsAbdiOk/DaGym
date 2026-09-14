import AVFAudio

/// Configures the shared `AVAudioSession` for on-device speech capture without stopping the
/// user's music any more than necessary, and restores it afterwards.
enum VoiceAudioSession {
    /// `.playAndRecord` so recording doesn't kill playback outright, `.duckOthers` so music
    /// quiets down for the hold instead of stopping, and Bluetooth options so AirPods (already
    /// connected for the workout) are used for both playback and the mic rather than falling
    /// back to the phone's speaker/mic mid-route.
    static func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord, mode: .measurement,
            options: [.duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Lets whatever was ducked come back up. Errors are swallowed — deactivating is always
    /// best-effort cleanup, never something a caller should have to handle.
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
