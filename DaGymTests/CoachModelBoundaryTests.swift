import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The `CoachLanguageModel` boundary (plan.md §6.6): model selection, the debrief facts
/// `finish` attaches, and the fallbacks that keep every feature working without a model.
@MainActor
@Suite("Coach model boundary")
struct CoachModelBoundaryTests {
    private func makePreferences(_ name: String) -> Preferences {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return Preferences(suite: defaults)
    }

    @Test("on-device AI defaults to on and persists")
    func preferenceDefaultsOn() {
        let preferences = makePreferences("coach.pref.default")
        #expect(preferences.onDeviceCoachEnabled)
        preferences.onDeviceCoachEnabled = false
        let reread = Preferences(suite: UserDefaults(suiteName: "coach.pref.default") ?? .standard)
        #expect(!reread.onDeviceCoachEnabled)
    }

    @Test("the toggle off always selects the rule model, with a status line that says so")
    func toggleOffSelectsRules() {
        let preferences = makePreferences("coach.pref.off")
        preferences.onDeviceCoachEnabled = false
        let services = CoachServices.make(preferences: preferences)
        #expect(services.model is RuleCoachModel)
        #expect(!services.isUsingLanguageModel)
        #expect(services.statusLine.hasPrefix("On-device AI: off"))
    }

    /// On this simulator Apple Intelligence is (almost certainly) unavailable, which is the
    /// branch this pins: the Foundation path reports a reason and the app falls back to the
    /// rules. On a device with Apple Intelligence on, the same test pins the other branch.
    @Test("with the toggle on, the choice follows the system's availability and names the reason")
    func toggleOnFollowsAvailability() {
        let preferences = makePreferences("coach.pref.on")
        let services = CoachServices.make(preferences: preferences)
        switch FoundationCoachModel().availability {
        case .available:
            #expect(services.model is FoundationCoachModel)
            #expect(services.statusLine == "On-device AI: ready")
        case .unavailable(let reason):
            #expect(services.model is RuleCoachModel)
            #expect(!reason.isEmpty)
            #expect(services.statusLine == "On-device AI: unavailable — \(reason)")
        }
    }

    /// The simulator has no Apple Intelligence, so `toggleOnFollowsAvailability` only ever sees
    /// one branch there. An injected model pins both: an available one is used and reported as
    /// the language model; an unavailable one falls back to the rules with its reason.
    @Test("with the toggle on, an available injected model is used and an unavailable one names its reason")
    func injectedModelPinsBothBranches() {
        let preferences = makePreferences("coach.pref.injected")
        let services = CoachServices.make(preferences: preferences)
        let mock = MockCoachModel()

        mock.availability = .available
        services.refresh(preferences: preferences, foundation: mock)
        #expect(services.model is MockCoachModel)
        #expect(services.isUsingLanguageModel)
        #expect(services.statusLine == "On-device AI: ready")

        mock.availability = .unavailable(reason: "the model is still downloading")
        services.refresh(preferences: preferences, foundation: mock)
        #expect(services.model is RuleCoachModel)
        #expect(!services.isUsingLanguageModel)
        #expect(services.statusLine == "On-device AI: unavailable — the model is still downloading")

        // The toggle off wins over an available model.
        mock.availability = .available
        preferences.onDeviceCoachEnabled = false
        services.refresh(preferences: preferences, foundation: mock)
        #expect(services.model is RuleCoachModel)
        #expect(!services.isUsingLanguageModel)
    }

    @Test("finishing a workout attaches debrief facts: skipped sets, sets below last, PR names")
    func finishAttachesDebriefFacts() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let sets = (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60) }
        let routine = store.saveRoutine(
            id: nil, name: "Push", rule: .linear(incrementKg: 2.5),
            exercises: [RoutineExerciseDraft(exerciseID: bench.id, sets: sets)]
        )
        // Session one: all three sets, so session two has a "last time" to fall short of.
        let first = store.startWorkout(routineID: routine.id)
        for index in 0..<3 {
            first.exercises[0].sets[index].weightKg = 60
            first.exercises[0].sets[index].reps = 8
            first.exercises[0].sets[index].isDone = true
        }
        let firstSummary = store.finish(session: first)
        let firstFacts = try #require(firstSummary.debriefFacts)
        #expect(firstFacts.setsDone == 3)
        #expect(firstFacts.previousVolumeKg == nil)
        #expect(firstFacts.personalRecords == ["Bench Press"])

        let second = store.startWorkout(routineID: routine.id)
        second.exercises[0].sets[0].reps = 8
        second.exercises[0].sets[0].isDone = true
        second.exercises[0].sets[1].reps = 6
        second.exercises[0].sets[1].isDone = true
        let secondSummary = store.finish(session: second)
        let facts = try #require(secondSummary.debriefFacts)
        #expect(facts.skippedSets == 1)
        #expect(facts.setsBelowLast == 1)
        #expect(facts.previousVolumeKg == firstSummary.volumeKg)
        #expect(facts.factIDs.contains(SessionSummaryFacts.FactID.volumeChange))
    }

    @Test("the rule model streams exactly one validated debrief, and a mock that fails yields none")
    func debriefStreams() async throws {
        let facts = SessionSummaryFacts(title: "Legs", durationMinutes: 40, volumeKg: 3_000, setsDone: 12)
        var seen: [SessionDebrief] = []
        for try await debrief in RuleCoachModel().debrief(facts: facts) { seen.append(debrief) }
        #expect(seen.count == 1)
        #expect(seen.first == DebriefRules.debrief(from: facts))

        let mock = MockCoachModel()
        mock.shouldFail = true
        await #expect(throws: CoachModelError.rejected) {
            for try await _ in mock.debrief(facts: facts) {}
        }
    }

    @Test("a model ranking is resolved to library rows, and an id outside the library is dropped")
    func rankingResolvesToLibrary() throws {
        let store = try makeStore()
        store.createProfile(name: "Gym", isActive: true, availableEquipment: ["barbell", "dumbbell"])
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let dumbbell = store.createCustomExercise(
            name: "Dumbbell Press", primary: [.chest], equipment: "dumbbell", style: .weightReps
        )
        let fly = store.createCustomExercise(
            name: "Dumbbell Fly", primary: [.chest], equipment: "dumbbell", style: .weightReps
        )
        let scored = store.scoredSubstitutes(for: bench.id, reason: .noBarbell)
        #expect(Set(scored.map(\.id)) == [dumbbell.id, fly.id])
        let ranked = [
            RankedSubstitute(candidateID: fly.id, why: "Isolates the chest"),
            RankedSubstitute(candidateID: UUID(), why: "Invented")
        ]
        let validated = try #require(SubstitutionRankingValidator.validate(ranked, candidates: scored))
        let suggestions = store.suggestions(from: validated)
        #expect(suggestions.map(\.exercise.id) == [fly.id, dumbbell.id])
        #expect(suggestions[0].why == "Isolates the chest")
    }
}
