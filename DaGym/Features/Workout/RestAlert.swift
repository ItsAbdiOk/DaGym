import AVFoundation
import Foundation

/// Synthesized rest-timer bleeps: a short 120 ms tone at 3-2-1 and one longer
/// 280 ms tone at 0. Runs the audio session as `.ambient` with `.duckOthers`
/// so a rest bleep lowers any playing music instead of stopping it, and — per
/// `.ambient`'s documented behaviour — stays silent when the ringer switch is
/// muted, the same way system alert sounds do.
@MainActor
final class RestAlertPlayer {
    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private let frequency = 1_000.0
    private var phase = 0.0
    private var samplesRemaining = 0
    private var isConfigured = false

    /// Plays a bleep. `longer` selects the final, longer tone played at 0.
    func bleep(longer: Bool = false) {
        configureIfNeeded()
        let duration = longer ? 0.28 : 0.12
        samplesRemaining = Int(duration * sampleRate)
        phase = 0
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.duckOthers])
        try? session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            self?.render(frameCount: frameCount, into: audioBufferList) ?? noErr
        }
        engine.attach(node)
        if let format {
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
        try? engine.start()
    }

    /// Renders a sine burst while `samplesRemaining > 0`, silence otherwise — the node stays
    /// attached and running so a bleep never pays the engine-start latency.
    private func render(
        frameCount: AVAudioFrameCount, into audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for frame in 0..<Int(frameCount) {
            var sample: Float = 0
            if samplesRemaining > 0 {
                sample = Float(sin(phase)) * 0.2
                phase += 2 * .pi * frequency / sampleRate
                samplesRemaining -= 1
            }
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
        return noErr
    }
}

/// Rest-alert toggles, read straight from `UserDefaults` under the keys the Settings agent's
/// `Preferences` type also writes to (`restSound`/`restHaptics`/`restScreenFlash`), so both
/// agents converge on the same storage before `Preferences` lands as a shared `@Observable`.
struct RestAlertPreferences {
    var sound: Bool
    var haptics: Bool
    var screenFlash: Bool

    static func current(defaults: UserDefaults = .standard) -> RestAlertPreferences {
        RestAlertPreferences(
            sound: defaults.object(forKey: "restSound") as? Bool ?? true,
            haptics: defaults.object(forKey: "restHaptics") as? Bool ?? true,
            screenFlash: defaults.object(forKey: "restScreenFlash") as? Bool ?? false
        )
    }
}
