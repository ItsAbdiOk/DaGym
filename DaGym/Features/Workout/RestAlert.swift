import AVFoundation
import Foundation
import Synchronization

/// Synthesized rest-timer bleeps: a short 120 ms tone at 3-2-1 and one longer
/// 280 ms tone at 0. Runs the audio session as plain `.ambient`, which mixes
/// with whatever is playing (music keeps going at full volume under the bleep —
/// `.duckOthers` is only valid with `.playback`, and that would ignore the ringer
/// switch) and stays silent when the ringer switch is muted, the same way
/// system alert sounds do.
@MainActor
final class RestAlertPlayer {
    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private let tone = ToneGenerator(sampleRate: 44_100, frequency: 1_000)
    private var isConfigured = false

    /// Plays a bleep. `longer` selects the final, longer tone played at 0.
    func bleep(longer: Bool = false) {
        configureIfNeeded()
        let duration = longer ? 0.28 : 0.12
        tone.play(samples: Int(duration * sampleRate))
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        let tone = tone
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            tone.render(frameCount: frameCount, into: audioBufferList)
        }
        engine.attach(node)
        if let format {
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
        try? engine.start()
    }
}

/// The part of the bleep that lives on Core Audio's real-time thread. Deliberately not
/// main-actor: `render` runs wherever the engine calls it, so the only state it shares with
/// the player is one atomic sample counter — no locks, no allocation, no actor hop.
private final class ToneGenerator: Sendable {
    private let sampleRate: Double
    private let frequency: Double
    private let amplitude: Float = 0.2
    private let samplesRemaining = Atomic<Int>(0)
    /// Touched only from the render thread: the sine phase, and the count seen on the previous
    /// callback so a fresh burst (count went up) restarts the phase at 0.
    nonisolated(unsafe) private var phase = 0.0
    nonisolated(unsafe) private var lastSeen = 0

    init(sampleRate: Double, frequency: Double) {
        self.sampleRate = sampleRate
        self.frequency = frequency
    }

    func play(samples: Int) {
        samplesRemaining.store(samples, ordering: .relaxed)
    }

    /// Renders a sine burst while samples remain, silence otherwise — the node stays attached
    /// and running so a bleep never pays the engine-start latency.
    func render(
        frameCount: AVAudioFrameCount, into audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let loaded = samplesRemaining.load(ordering: .relaxed)
        if loaded > lastSeen { phase = 0 }
        var remaining = loaded
        let step = 2 * Double.pi * frequency / sampleRate
        for frame in 0..<Int(frameCount) {
            var sample: Float = 0
            if remaining > 0 {
                sample = Float(sin(phase)) * amplitude
                phase += step
                remaining -= 1
            }
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
        // A `play` that landed mid-callback wins: the exchange fails and its count is kept.
        _ = samplesRemaining.compareExchange(expected: loaded, desired: remaining, ordering: .relaxed)
        lastSeen = remaining
        return noErr
    }
}
