import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Voice logging (plan: DaGym/Services/Voice + DaGym/Features/Voice), driven entirely through a
/// scripted `FakeSpeechRecognizer` — no audio hardware, no `Speech`/`AVFAudio`.
@MainActor
@Suite("VoiceLogController")
struct VoiceLogControllerTests {
    /// A name with zero token or character overlap with anything spoken in these tests, so
    /// `ExerciseMatcher` can never accidentally resolve it — used where a test needs the on-deck
    /// exercise to be a definite non-match rather than relying on real exercise names sounding
    /// similar or different by chance.
    private static let unrelatedExerciseName = "Xylophone Postal Vortex"

    private func exercise(_ name: String = "Bench Press", increment: Double = 2.5) -> ExerciseInfo {
        ExerciseInfo(
            name: name, primary: [.chest], equipment: "Barbell", incrementKg: increment, bar: .olympic
        )
    }

    private func session(
        exerciseName: String = "Bench Press", weightKg: Double = 100, reps: Int = 8
    ) -> WorkoutSession {
        let entry = WorkoutExerciseEntry(
            exercise: exercise(exerciseName), sets: [SetEntry(weightKg: weightKg, reps: reps)]
        )
        let session = WorkoutSession(title: "Push", subtitle: "", startedAt: Date(), exercises: [entry])
        session.restHaptics = false
        return session
    }

    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makePreferences(unit: WeightUnit = .lb) -> Preferences {
        let suite = UserDefaults(suiteName: "VoiceLogControllerTests-\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(suite: suite)
        preferences.weightUnit = unit
        return preferences
    }

    // MARK: 1 — high-confidence auto-logs and is undoable

    @Test("a high-confidence, single-set transcript auto-logs and is undoable")
    func autoLogsAndUndoes() async throws {
        let session = session(weightKg: 0, reps: 0)
        let store = try makeStore()
        let preferences = makePreferences(unit: .lb)
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [.final("8 reps at 225 pounds")]
        let controller = VoiceLogController(recognizer: recognizer, speaker: FakeVoiceSpeechSynthesizer())

        controller.startHolding()
        await controller.waitForListening()
        var loggedUndo: UndoAction?
        controller.stopHolding(session: session, store: store, preferences: preferences) { loggedUndo = $0 }

        guard case .autoLogged = controller.state else {
            Issue.record("expected .autoLogged, got \(controller.state)")
            return
        }
        let set = session.exercises[0].sets[0]
        #expect(set.isDone)
        #expect(set.reps == 8)
        // 225 lb ≈ 102.06 kg, snapped to whatever's loadable on a standard olympic bar/plate set.
        #expect(abs(set.weightKg - 102.06) < 2.5)

        let undo = try #require(loggedUndo)
        undo.undo()
        #expect(session.exercises[0].sets[0].isDone == false)
        #expect(session.exercises[0].sets[0].reps == 0)
    }

    // MARK: 2 — low confidence (here: more than one set) shows the card instead

    @Test("a multi-set transcript always opens the review card, never auto-logs")
    func multiSetShowsCard() async throws {
        let session = session(weightKg: 0, reps: 0)
        let store = try makeStore()
        let preferences = makePreferences(unit: .kg)
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [.final("three sets of eight at sixty")]
        let controller = VoiceLogController(recognizer: recognizer, speaker: FakeVoiceSpeechSynthesizer())

        controller.startHolding()
        await controller.waitForListening()
        controller.stopHolding(session: session, store: store, preferences: preferences) { _ in
            Issue.record("a multi-set command must never auto-log")
        }

        guard case .reviewing(let card) = controller.state else {
            Issue.record("expected .reviewing, got \(controller.state)")
            return
        }
        #expect(card.weightKg == 60)
        #expect(card.reps == 8)
        // Nothing was written until the card is confirmed.
        #expect(session.exercises[0].sets[0].isDone == false)
    }

    // MARK: 3 — exercise not in session

    @Test("naming an exercise nothing in the session resembles is rejected, not silently logged")
    func exerciseNotInSessionIsRejected() async throws {
        let session = session(exerciseName: Self.unrelatedExerciseName, weightKg: 0, reps: 0)
        let store = try makeStore()
        let preferences = makePreferences(unit: .kg)
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [.final("twelve pull ups")]
        let controller = VoiceLogController(recognizer: recognizer, speaker: FakeVoiceSpeechSynthesizer())

        controller.startHolding()
        await controller.waitForListening()
        controller.stopHolding(session: session, store: store, preferences: preferences) { _ in
            Issue.record("an unresolved exercise must never auto-log")
        }

        guard case .error(let error) = controller.state else {
            Issue.record("expected .error, got \(controller.state)")
            return
        }
        guard case .exerciseNotInSession = error else {
            Issue.record("expected .exerciseNotInSession, got \(error)")
            return
        }
        #expect(session.exercises[0].sets[0].isDone == false)
    }

    // MARK: 4 — permission denied

    @Test("permission denied surfaces the denied state and never starts audio")
    func permissionDeniedNeverStartsAudio() async throws {
        let recognizer = FakeSpeechRecognizer(authorizationStatus: .deniedMicrophone)
        let controller = VoiceLogController(recognizer: recognizer, speaker: FakeVoiceSpeechSynthesizer())

        controller.startHolding()
        await controller.waitForListening()

        guard case .error(.permissionDenied) = controller.state else {
            Issue.record("expected .error(.permissionDenied), got \(controller.state)")
            return
        }
        #expect(recognizer.startListeningCallCount == 0)
    }

    @Test("not-yet-determined permission is requested once, then proceeds if granted")
    func requestsPermissionWhenNotDetermined() async throws {
        let session = session(weightKg: 0, reps: 0)
        let store = try makeStore()
        let preferences = makePreferences(unit: .kg)
        let recognizer = FakeSpeechRecognizer(
            authorizationStatus: .notDetermined, authorizationToGrant: .authorized
        )
        recognizer.scriptedEvents = [.final("done")]
        let controller = VoiceLogController(recognizer: recognizer, speaker: FakeVoiceSpeechSynthesizer())

        controller.startHolding()
        await controller.waitForListening()
        controller.stopHolding(session: session, store: store, preferences: preferences) { _ in }

        #expect(recognizer.authorizationStatus == .authorized)
        #expect(recognizer.startListeningCallCount == 1)
    }

    // MARK: 5 — released mid-recognition tears down cleanly

    @Test("cancelling mid-recognition tears down without touching the session")
    func cancelMidRecognitionTearsDownCleanly() async throws {
        let session = session(weightKg: 100, reps: 8)
        let recognizer = FakeSpeechRecognizer()
        // Never finishes on its own — models a recognizer still listening, so cancelling genuinely
        // interrupts an in-flight recognition instead of racing a stream that already ended.
        recognizer.finishesAutomatically = false
        recognizer.scriptedEvents = [.partial("one twenty")]
        let controller = VoiceLogController(recognizer: recognizer, speaker: FakeVoiceSpeechSynthesizer())

        controller.startHolding()
        // Give the listen loop a real turn of the run loop to reach its in-flight state before
        // cancelling — `startHolding()` schedules a `Task` that hasn't necessarily run yet the
        // instant this call returns.
        try? await Task.sleep(for: .milliseconds(20))
        #expect(recognizer.startListeningCallCount == 1)
        if case .listening = controller.state {} else {
            Issue.record("expected still-listening before cancel, got \(controller.state)")
        }

        controller.cancel()

        #expect(controller.state == .idle)
        #expect(recognizer.stopListeningCallCount == 1)
        // Nothing about the session was touched by a cancelled hold.
        #expect(session.exercises[0].sets[0].isDone == false)
        #expect(session.exercises[0].sets[0].weightKg == 100)
    }
}
