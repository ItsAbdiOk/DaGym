import AVFoundation
import Foundation
import Synchronization
import os

private let restLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "rest")

/// Synthesized rest-timer bleeps: a short 120 ms tone at 3-2-1 and one longer
/// 280 ms tone at 0. Runs the audio session as plain `.ambient`, which mixes
/// with whatever is playing (music keeps going at full volume under the bleep —
/// `.duckOthers` is only valid with `.playback`, and that would ignore the ringer
/// switch) and stays silent when the ringer switch is muted, the same way
/// system alert sounds do.
@MainActor
final class RestAlertPlayer {
    /// Mirrors `Preferences.playRestSoundOnSilent`. Pushed in by `ActiveWorkoutView` (on appear
    /// and on every change) rather than read back out of `UserDefaults` by raw key: this class
    /// has no `@Environment` access, but reaching around `Preferences` to a string key meant a
    /// renamed key would fail silently instead of failing to compile.
    var playsOnSilent = false

    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private let tone = ToneGenerator(sampleRate: 44_100, frequency: 1_000)
    private var isEngineConfigured = false

    /// Plays a bleep. `longer` selects the final, longer tone played at 0.
    func bleep(longer: Bool = false) {
        configureEngineIfNeeded()
        updateSessionCategoryIfNeeded()
        let duration = longer ? 0.28 : 0.12
        tone.play(samples: Int(duration * sampleRate))
    }

    private func configureEngineIfNeeded() {
        guard !isEngineConfigured else { return }
        isEngineConfigured = true
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        let tone = tone
        // `@Sendable` keeps the render block nonisolated: AVFAudio marks it non-Sendable, so a
        // plain closure here would inherit this class's main-actor isolation and Swift 6's
        // runtime check would trap on the realtime thread (see `VoiceAuthorization.request()`).
        let node = AVAudioSourceNode { @Sendable _, _, frameCount, audioBufferList in
            tone.render(frameCount: frameCount, into: audioBufferList)
        }
        engine.attach(node)
        if let format {
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Logged, not surfaced: a workout with no bleep is still a workout. But "no rest
            // sound" is otherwise undiagnosable from a user report.
            restLogger.error(
                "Rest bleep engine failed to start: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// `.ambient` mixes with whatever is playing and stays silent when the ringer switch is
    /// muted, the same way system alert sounds do. Opting into "Play on silent" switches to
    /// `.playback`, which pauses other audio but ignores the ringer switch — the Settings toggle
    /// that flips `playsOnSilent` says so. Re-checked (cheaply) on every bleep rather than once,
    /// so toggling the setting mid-workout takes effect on the very next rest timer.
    ///
    /// Two coordination rules, both learned the hard way:
    ///
    /// * While voice logging holds the session (`VoiceAudioSession.isRecordingActive`) this does
    ///   nothing. Changing the category under a running `AVAudioEngine` stops that engine with
    ///   its input tap still installed — the partial transcript freezes, and the release logs
    ///   whatever truncated number was on screen.
    /// * The decision is made against the session's *current* category rather than a remembered
    ///   flag, so after voice logging hands the session back (restoring the previous category)
    ///   the next bleep re-applies what it needs instead of assuming it's still in force.
    private func updateSessionCategoryIfNeeded() {
        guard !VoiceAudioSession.isRecordingActive else { return }
        let desired: AVAudioSession.Category = playsOnSilent ? .playback : .ambient
        let session = AVAudioSession.sharedInstance()
        guard session.category != desired else { return }
        do {
            try session.setCategory(desired)
            try session.setActive(true)
        } catch {
            let category = desired.rawValue
            let reason = error.localizedDescription
            restLogger.error(
                "Rest bleep audio session (\(category, privacy: .public)) failed: \(reason, privacy: .public)"
            )
        }
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
