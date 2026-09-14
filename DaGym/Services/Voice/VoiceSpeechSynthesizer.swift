import AVFAudio
import Foundation

/// Speaks a short confirmation back to the user. The seam so `VoiceLogController` can be tested
/// without touching `AVSpeechSynthesizer`/`AVAudioSession`.
@MainActor
protocol VoiceSpeechSynthesizing: AnyObject {
    /// True when audio is currently routed to something being *worn* rather than something
    /// broadcasting to a room — `VoiceLogController` only speaks back when this is true
    /// (`Preferences.voiceSpeakBackOnHeadphones`).
    var isRoutedToHeadphones: Bool { get }
    func speak(_ text: String)
}

@MainActor
final class VoiceSpeechSynthesizer: VoiceSpeechSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()
    /// `nonisolated(unsafe)` so `deinit` can unregister it: touched only in `init` and `deinit`,
    /// never concurrently.
    nonisolated(unsafe) private var routeObserver: NSObjectProtocol?

    init() {
        // The route can change mid-utterance — AirPods pulled out, a car handing the phone back
        // to its own speaker. Stop talking rather than finishing the sentence out loud.
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                  reason == .oldDeviceUnavailable || reason == .override else { return }
            Task { @MainActor in self?.stopSpeaking() }
        }
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    /// Wired headphones are unambiguous. Bluetooth is not: A2DP/HFP covers AirPods *and* the
    /// speaker bolted to the wall of a gym or sitting in a car's dashboard, and iOS exposes no
    /// "is anyone wearing this" flag. The tie-breaker we do have is a microphone — a Bluetooth
    /// port that also appears as an available *input* is a headset on someone's head, not a
    /// speaker pointed at a room. Anything else stays silent: a missed confirmation costs
    /// nothing, announcing "Bench Press 100 kg × 8" to a gym is not recoverable.
    var isRoutedToHeadphones: Bool {
        let session = AVAudioSession.sharedInstance()
        let inputIdentifiers = Set((session.availableInputs ?? []).map { Self.deviceIdentifier($0.uid) })
        return session.currentRoute.outputs.contains { output in
            switch output.portType {
            case .headphones:
                return true
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return inputIdentifiers.contains(Self.deviceIdentifier(output.uid))
            default:
                return false
            }
        }
    }

    /// One Bluetooth device shows up under several port UIDs — the A2DP output is the device
    /// address with a profile suffix ("…-tacl"), the HFP input is the bare address. Comparing
    /// the part before the first "-" is what lets one device's output and input be recognised as
    /// the same piece of hardware.
    private static func deviceIdentifier(_ uid: String) -> String {
        String(uid.prefix(while: { $0 != "-" }))
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
