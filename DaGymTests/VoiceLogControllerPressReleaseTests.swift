import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The press/release edges around a mic that hasn't opened yet — the first-ever tap, where the
/// two permission sheets cancel the gesture under the finger, and a release that lands while
/// the recogniser is still waiting for its audio route. Neither may crash, log, or complain
/// about silence the user never had a chance to break.
@MainActor
@Suite("VoiceLogController press/release before the mic opens")
struct VoiceLogControllerPressReleaseTests {
    @Test("a release during the permission sheet goes quiet, and the grant does not start listening")
    func releaseDuringPermissionPromptGoesIdle() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer(
            authorizationStatus: .notDetermined, authorizationToGrant: .authorized
        )
        recognizer.authorizationDelay = .milliseconds(60)
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        try? await Task.sleep(for: .milliseconds(10))
        // The sheet cancelled the drag: release arrives with the prompt still up.
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in
            Issue.record("a release before the mic opened must never log")
        }
        #expect(controller.state == .idle)
        #expect(recognizer.endAudioCallCount == 0)

        await controller.waitForListening()
        // Granted — but nobody is holding the button any more, so the mic stays closed.
        #expect(recognizer.authorizationStatus == .authorized)
        #expect(recognizer.startListeningCallCount == 0)
        #expect(controller.state == .idle)
    }

    @Test("a denial answered after the release is still reported, not swallowed by the release")
    func denialAfterReleaseIsReported() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer(
            authorizationStatus: .notDetermined, authorizationToGrant: .deniedMicrophone
        )
        recognizer.authorizationDelay = .milliseconds(60)
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        try? await Task.sleep(for: .milliseconds(10))
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in
            Issue.record("a denied hold must never log")
        }
        #expect(controller.state == .idle)

        await controller.waitForListening()
        #expect(controller.state == .error(.permissionDenied))
        #expect(recognizer.startListeningCallCount == 0)
    }

    @Test("a release while the route is still settling closes the mic once it opens")
    func releaseDuringStartClosesTheMic() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer()
        recognizer.startDelay = .milliseconds(60)
        recognizer.finishesAutomatically = false
        recognizer.scriptedEvents = [.partial("one twenty")]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        try? await Task.sleep(for: .milliseconds(10))
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in
            Issue.record("a release before the mic opened must never log")
        }
        #expect(controller.state == .idle)

        await controller.waitForListening()
        #expect(recognizer.startListeningCallCount == 1)
        #expect(recognizer.stopListeningCallCount == 1)
        #expect(controller.state == .idle)
        #expect(workout.exercises[0].sets[0].isDone == false)
    }

    @Test("a new press during a slow permission answer owns the controller; the old answer is dropped")
    func stalePromptAnswerDoesNotOverwriteNewPress() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer(
            authorizationStatus: .notDetermined, authorizationToGrant: .deniedMicrophone
        )
        recognizer.authorizationDelay = .milliseconds(60)
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        try? await Task.sleep(for: .milliseconds(10))
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in }
        // Second press before the first prompt has answered. Its own prompt answers too.
        controller.startHolding()
        try? await Task.sleep(for: .milliseconds(150))

        // One denied result, from the press that is current — not one per press.
        #expect(controller.state == .error(.permissionDenied))
        controller.cancel()
        #expect(controller.state == .idle)
    }

    @Test("a start failure surfaces as an audio hiccup and the release keeps it")
    func startFailureIsKeptByRelease() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer()
        recognizer.startError = .audioEngineUnavailable
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        #expect(controller.state == .error(.audioFailure))
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in
            Issue.record("a failed start must never log")
        }
        #expect(controller.state == .error(.audioFailure))
        #expect(recognizer.endAudioCallCount == 0)
    }

    @Test("on-device unavailable is its own error, not a generic hiccup")
    func onDeviceUnavailableIsSpecific() async throws {
        let recognizer = FakeSpeechRecognizer()
        recognizer.startError = .onDeviceUnavailable
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        #expect(controller.state == .error(.onDeviceUnavailable))
    }
}
