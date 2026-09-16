import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The two ends of a voice turn that only misbehave against real audio hardware, pinned down
/// with the fakes: what a "nothing said" recognition error becomes, and *when* the headphone
/// route is checked for speak-back.
@MainActor
@Suite("Voice services")
struct ServiceVoiceTests {
    // MARK: Recognizer error mapping

    @Test("Speech's 'no speech detected' error becomes .noSpeechDetected, not an audio failure")
    func noSpeechErrorIsNothingHeard() {
        let error = NSError(domain: "kAFAssistantErrorDomain", code: 1110)

        let mapped = OnDeviceSpeechRecognizer.failure(for: error, hadTranscript: false)

        #expect(mapped as? SpeechRecognitionFailure == .noSpeechDetected)
    }

    @Test("any recognition error before a word was heard is 'nothing heard'")
    func errorBeforeAnyTranscriptIsNothingHeard() {
        let error = NSError(domain: "SomeOtherDomain", code: 42)

        let mapped = OnDeviceSpeechRecognizer.failure(for: error, hadTranscript: false)

        #expect(mapped as? SpeechRecognitionFailure == .noSpeechDetected)
    }

    @Test("a recognition error after words were heard passes through unchanged")
    func errorAfterTranscriptIsForwarded() {
        let error = NSError(domain: "SomeOtherDomain", code: 42)

        let mapped = OnDeviceSpeechRecognizer.failure(for: error, hadTranscript: true)

        #expect((mapped as NSError).domain == "SomeOtherDomain")
        #expect((mapped as NSError).code == 42)
    }

    // MARK: Speak-back route timing

    private func autoLogPreferences() -> Preferences {
        let suite = UserDefaults(suiteName: "ServiceVoiceTests-\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(suite: suite)
        preferences.weightUnit = .lb
        preferences.voiceAutoLogEnabled = true
        preferences.voiceSpeakBackOnHeadphones = true
        return preferences
    }

    private func session() -> WorkoutSession {
        let exercise = ExerciseInfo(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", incrementKg: 2.5, bar: .olympic
        )
        let entry = WorkoutExerciseEntry(exercise: exercise, sets: [SetEntry(weightKg: 0, reps: 0)])
        let session = WorkoutSession(title: "Push", subtitle: "", startedAt: Date(), exercises: [entry])
        session.restHaptics = false
        return session
    }

    /// A Bluetooth headset only shows a microphone while the recording session is live, so the
    /// route has to be judged when the mic opens. Here it says "worn" during the hold and "not
    /// worn" by release — exactly what AirPods look like once the session is put back — and the
    /// confirmation must still be spoken.
    @Test("speak-back uses the route as it was when listening started, not at release")
    func speakBackUsesTheRouteAtListenStart() async throws {
        let session = session()
        let store = try makeStore()
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [.final(SpeechTranscript("8 reps at 225 pounds", confidence: 0.96))]
        let speaker = FakeVoiceSpeechSynthesizer()
        speaker.isRoutedToHeadphones = true
        let controller = VoiceLogController(recognizer: recognizer, speaker: speaker)

        controller.startHolding()
        await controller.waitForListening()
        speaker.isRoutedToHeadphones = false
        let preferences = autoLogPreferences()
        await controller.stopHolding(session: session, store: store, preferences: preferences) { _ in }

        guard case .autoLogged = controller.state else {
            Issue.record("expected .autoLogged, got \(controller.state)")
            return
        }
        #expect(speaker.spoken.count == 1)
    }

    @Test("no speak-back when nothing worn was on the route while listening")
    func noSpeakBackWithoutHeadphonesAtListenStart() async throws {
        let session = session()
        let store = try makeStore()
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [.final(SpeechTranscript("8 reps at 225 pounds", confidence: 0.96))]
        let speaker = FakeVoiceSpeechSynthesizer()
        speaker.isRoutedToHeadphones = false
        let controller = VoiceLogController(recognizer: recognizer, speaker: speaker)

        controller.startHolding()
        await controller.waitForListening()
        let preferences = autoLogPreferences()
        await controller.stopHolding(session: session, store: store, preferences: preferences) { _ in }

        #expect(speaker.spoken.isEmpty)
    }
}
