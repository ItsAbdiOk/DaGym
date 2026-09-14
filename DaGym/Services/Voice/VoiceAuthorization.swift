import AVFAudio
import Speech

/// The combined outcome of the speech-recognition and microphone permission prompts — the two
/// permissions `SpeechRecognizing` needs, collapsed into one status so the UI has a single
/// denied/restricted state to design for instead of a 2×2 matrix.
enum VoiceAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    /// Speech recognition itself was denied in Settings.
    case deniedSpeech
    /// Speech recognition is fine; the microphone was denied.
    case deniedMicrophone
    /// Parental controls or an MDM profile blocks speech recognition on this device.
    case restricted
}

/// Reads and requests the two permissions `SpeechRecognizing` needs. Kept separate from
/// `OnDeviceSpeechRecognizer` so a fake recognizer in tests never has to touch `Speech`/`AVFAudio`.
@MainActor
enum VoiceAuthorization {
    static func currentStatus() -> VoiceAuthorizationStatus {
        combined(
            speech: SFSpeechRecognizer.authorizationStatus(),
            mic: AVAudioApplication.shared.recordPermission
        )
    }

    /// Speech first, then (only if granted) the microphone — asking for the mic when speech was
    /// just denied would show a permission sheet for a feature that can't work anyway.
    private typealias SpeechContinuation = CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>

    static func request() async -> VoiceAuthorizationStatus {
        let speech = await withCheckedContinuation { (continuation: SpeechContinuation) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else {
            return combined(speech: speech, mic: AVAudioApplication.shared.recordPermission)
        }
        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return combined(
            speech: speech, mic: micGranted ? .granted : .denied
        )
    }

    private static func combined(
        speech: SFSpeechRecognizerAuthorizationStatus, mic: AVAudioApplication.recordPermission
    ) -> VoiceAuthorizationStatus {
        switch speech {
        case .notDetermined: return .notDetermined
        case .denied: return .deniedSpeech
        case .restricted: return .restricted
        case .authorized:
            switch mic {
            case .granted: return .authorized
            case .denied: return .deniedMicrophone
            case .undetermined: return .notDetermined
            @unknown default: return .deniedMicrophone
            }
        @unknown default: return .restricted
        }
    }
}
