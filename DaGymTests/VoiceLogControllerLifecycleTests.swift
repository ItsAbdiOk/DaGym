import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The hold-to-talk turn's edges: an error raised under the finger surviving the release, the
/// re-press race, and the truncated partial that must never be what gets logged. Driven entirely
/// through `FakeSpeechRecognizer` — no audio hardware, no `Speech`. Where a set *lands* once
/// parsed is `VoiceLogControllerTargetingTests`.
@MainActor
@Suite("VoiceLogController lifecycle")
struct VoiceLogControllerLifecycleTests {
    // MARK: Errors raised while the finger is down survive the release

    @Test("releasing after a permission error keeps the error instead of \u{201C}Didn't catch that\u{201D}")
    func releaseKeepsPermissionError() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let recognizer = FakeSpeechRecognizer(authorizationStatus: .deniedMicrophone)
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        await controller.stopHolding(
            session: workout, store: store, preferences: VoiceLogFixtures.preferences()
        ) { _ in Issue.record("a denied hold must never log") }

        #expect(controller.state == .error(.permissionDenied))
    }

    @Test("a restricted device gets restriction copy, not \u{201C}turn it on in Settings\u{201D}")
    func restrictedSurfacesItsOwnError() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let recognizer = FakeSpeechRecognizer(authorizationStatus: .restricted)
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        await controller.stopHolding(
            session: workout, store: store, preferences: VoiceLogFixtures.preferences()
        ) { _ in Issue.record("a restricted hold must never log") }

        #expect(controller.state == .error(.permissionRestricted))
    }

    // MARK: Re-press while the previous release is still waiting for its final hypothesis

    @Test("a new press during the previous release's wait is not torn down by it")
    func rePressDuringReleaseWindowSurvives() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer()
        // Still deciding: neither the stream nor `endAudio()` ends it, so the release genuinely
        // sits in its bounded wait — the window a second press has to land in.
        recognizer.finishesAutomatically = false
        recognizer.finishesOnEndAudio = false
        recognizer.scriptedEvents = [.partial("one twenty")]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        try? await Task.sleep(for: .milliseconds(20))
        let release = Task {
            await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in
                Issue.record("a release that lost its turn must never log")
            }
        }
        try? await Task.sleep(for: .milliseconds(30))
        controller.startHolding()
        await release.value
        try? await Task.sleep(for: .milliseconds(30))

        #expect(recognizer.startListeningCallCount == 2)
        // The stale release must not have stopped the stream the new press just opened.
        #expect(recognizer.stopListeningCallCount == 0)
        if case .listening = controller.state {} else {
            Issue.record("expected the new press to still be listening, got \(controller.state)")
        }
        #expect(workout.exercises[0].sets[0].isDone == false)
        controller.cancel()
    }

    // MARK: A truncated partial is never what gets logged

    @Test("the final hypothesis, not the partial on screen at release, is what is logged")
    func finalHypothesisWinsOverTruncatedPartial() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let preferences = VoiceLogFixtures.preferences(unit: .kg, autoLog: true)
        let recognizer = FakeSpeechRecognizer()
        recognizer.finishesAutomatically = false
        // What's on screen when the finger lifts a beat early…
        recognizer.scriptedEvents = [.partial("eight reps at 1")]
        // …and what the recognizer actually committed to once the audio stopped.
        recognizer.finalAfterEndAudio = SpeechTranscript("eight reps at 100", confidence: 0.95)
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        try? await Task.sleep(for: .milliseconds(20))
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in }

        #expect(recognizer.endAudioCallCount == 1)
        let set = workout.exercises[0].sets[0]
        #expect(set.isDone)
        #expect(set.reps == 8)
        #expect(set.weightKg == 100)
    }

    @Test("a truncated partial with no final hypothesis never auto-logs")
    func truncatedPartialNeverAutoLogs() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try makeStore()
        let preferences = VoiceLogFixtures.preferences(unit: .kg, autoLog: true)
        let recognizer = FakeSpeechRecognizer()
        recognizer.finishesAutomatically = false
        recognizer.scriptedEvents = [.partial("eight reps at 1")]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        try? await Task.sleep(for: .milliseconds(20))
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in
            Issue.record("a partial with no recognition confidence must never auto-log")
        }

        if case .autoLogged = controller.state {
            Issue.record("a truncated partial auto-logged: \(controller.state)")
        }
        #expect(workout.exercises[0].sets[0].isDone == false)
    }
}
