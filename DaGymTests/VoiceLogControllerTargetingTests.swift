import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Where a spoken set actually lands: the right exercise row when one appears twice, the right
/// set kind, every set of a multi-set command, and the user's own unit. Each of these used to be
/// a silent wrong write rather than a visible failure.
@MainActor
@Suite("VoiceLogController targeting")
struct VoiceLogControllerTargetingTests {
    // MARK: The same exercise twice in one session

    @Test("a set lands on the block still being worked, not the finished earlier one")
    func duplicateExerciseTargetsThePendingBlock() async throws {
        let bench = VoiceLogFixtures.exercise()
        let squat = VoiceLogFixtures.exercise("Squat")
        let workout = VoiceLogFixtures.session([
            WorkoutExerciseEntry(exercise: bench, sets: [SetEntry(weightKg: 60, reps: 10, isDone: true)]),
            WorkoutExerciseEntry(exercise: squat, sets: [SetEntry(weightKg: 80, reps: 5)]),
            WorkoutExerciseEntry(exercise: bench, sets: [SetEntry(weightKg: 0, reps: 0)])
        ])
        let store = try VoiceLogFixtures.store()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [
            .final(SpeechTranscript("bench press 100 for 8", confidence: 0.95))
        ]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in }

        guard case .reviewing(let card) = controller.state else {
            Issue.record("expected .reviewing, got \(controller.state)")
            return
        }
        #expect(card.entryID == workout.exercises[2].id)

        controller.confirmReview(
            card, session: workout, store: store, preferences: preferences
        ) { _ in }
        #expect(workout.exercises[2].sets[0].isDone)
        #expect(workout.exercises[2].sets[0].reps == 8)
        // The finished earlier block keeps exactly what it had.
        #expect(workout.exercises[0].sets.count == 1)
        #expect(workout.exercises[0].sets[0].weightKg == 60)
        #expect(workout.exercises[0].sets[0].reps == 10)
    }

    // MARK: A spoken set kind never rewrites a planned set

    @Test("\u{201C}drop set\u{201D} adds a drop set, leaving the planned working set planned")
    func setKindDoesNotConvertThePlannedSet() async throws {
        let workout = VoiceLogFixtures.session([WorkoutExerciseEntry(
            exercise: VoiceLogFixtures.exercise(), sets: [SetEntry(kind: .working, weightKg: 100, reps: 8)]
        )])
        let store = try VoiceLogFixtures.store()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [
            .final(SpeechTranscript("drop set 60 for 12", confidence: 0.95))
        ]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in }

        guard case .reviewing(let card) = controller.state else {
            Issue.record("expected .reviewing, got \(controller.state)")
            return
        }
        controller.confirmReview(
            card, session: workout, store: store, preferences: preferences
        ) { _ in }

        let sets = workout.exercises[0].sets
        #expect(sets.count == 2)
        #expect(sets[0].kind == .working)
        #expect(sets[0].isDone == false)
        #expect(sets[0].weightKg == 100)
        #expect(sets[1].kind == .drop)
        #expect(sets[1].isDone)
        #expect(sets[1].weightKg == 60)
        #expect(sets[1].reps == 12)
    }

    // MARK: Confirming a multi-set card writes every set

    @Test("confirming \u{201C}three sets of eight at sixty\u{201D} writes three sets, not one")
    func confirmingMultiSetWritesEverySet() async throws {
        let workout = VoiceLogFixtures.session([WorkoutExerciseEntry(
            exercise: VoiceLogFixtures.exercise(),
            sets: [
                SetEntry(weightKg: 0, reps: 0), SetEntry(weightKg: 0, reps: 0),
                SetEntry(weightKg: 0, reps: 0)
            ]
        )])
        let store = try VoiceLogFixtures.store()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [
            .final(SpeechTranscript("three sets of eight at sixty", confidence: 0.95))
        ]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in }

        guard case .reviewing(let card) = controller.state else {
            Issue.record("expected .reviewing, got \(controller.state)")
            return
        }
        #expect(card.setCount == 3)
        controller.confirmReview(
            card, session: workout, store: store, preferences: preferences
        ) { _ in }

        #expect(workout.exercises[0].sets.count == 3)
        #expect(workout.exercises[0].sets.allSatisfy { $0.isDone })
        #expect(workout.exercises[0].sets.allSatisfy { $0.reps == 8 && $0.weightKg == 60 })
    }

    @Test("an edited review card still goes through the validator")
    func editedCardIsValidated() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try VoiceLogFixtures.store()
        let preferences = VoiceLogFixtures.preferences()
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [
            .final(SpeechTranscript("eight reps at 100", confidence: 0.95))
        ]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in }

        guard case .reviewing(var card) = controller.state else {
            Issue.record("expected .reviewing, got \(controller.state)")
            return
        }
        card.weightKg = 5_000
        controller.confirmReview(
            card, session: workout, store: store, preferences: preferences
        ) { _ in Issue.record("5000 kg must never reach the session") }

        #expect(controller.state == .error(.valueOutOfRange))
        #expect(workout.exercises[0].sets[0].isDone == false)
    }

    // MARK: lb users are shown and told lb

    @Test("an lb user's card and confirmation are in pounds, never kg")
    func poundsUserSeesPounds() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try VoiceLogFixtures.store()
        let preferences = VoiceLogFixtures.preferences(unit: .lb, autoLog: true)
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [
            .final(SpeechTranscript("8 reps at 225 pounds", confidence: 0.96))
        ]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in }

        guard case .autoLogged(let message) = controller.state else {
            Issue.record("expected .autoLogged, got \(controller.state)")
            return
        }
        #expect(message.contains("lb"))
        #expect(!message.contains("kg"))
    }

    @Test("an lb user's review card carries the lb unit, so edits are read as pounds")
    func poundsUserCardCarriesUnit() async throws {
        let workout = VoiceLogFixtures.singleSetSession()
        let store = try VoiceLogFixtures.store()
        let preferences = VoiceLogFixtures.preferences(unit: .lb)
        let recognizer = FakeSpeechRecognizer()
        recognizer.scriptedEvents = [
            .final(SpeechTranscript("8 reps at 225 pounds", confidence: 0.96))
        ]
        let controller = VoiceLogFixtures.controller(recognizer)

        controller.startHolding()
        await controller.waitForListening()
        await controller.stopHolding(session: workout, store: store, preferences: preferences) { _ in }

        guard case .reviewing(let card) = controller.state else {
            Issue.record("expected .reviewing, got \(controller.state)")
            return
        }
        #expect(card.unit == .lb)
        // Stored canonically in kg — it's the card's `unit` that turns it back into pounds.
        #expect(abs((card.weightKg ?? 0) - 102.06) < 2.5)
    }
}
