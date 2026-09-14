import AVFAudio
import Foundation

/// Speaks a short confirmation back to the user. The seam so `VoiceLogController` can be tested
/// without touching `AVSpeechSynthesizer`/`AVAudioSession`.
@MainActor
protocol VoiceSpeechSynthesizing: AnyObject {
    /// True when audio is currently routed to headphones/AirPods rather than the phone speaker —
    /// `VoiceLogController` only speaks back when this is true (Preferences.voiceSpeakBackOnHeadphones).
    var isRoutedToHeadphones: Bool { get }
    func speak(_ text: String)
}

@MainActor
final class VoiceSpeechSynthesizer: VoiceSpeechSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()

    var isRoutedToHeadphones: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: true
            default: false
            }
        }
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
