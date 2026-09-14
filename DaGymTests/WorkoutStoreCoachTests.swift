import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore coach adapter")
struct WorkoutStoreCoachTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    /// A routine with one exercise, a finished session, and a stalled `RoutineExerciseModel`
    /// (3 consecutive misses at 80 kg) — enough for `CoachRules.stalledLiftCards` to fire, with a
    /// `.deloadExercise` suggested action.
    @discardableResult
    private func stalledLift(_ store: WorkoutStore, name: String = "Bench Press") -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: name, primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let workingSet = PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)
        let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: [workingSet])
        let routine = store.saveRoutine(
            id: nil, name: name, rule: .linear(incrementKg: 2.5), exercises: [draft]
        )
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].weightKg = 80
        session.exercises[0].sets[0].reps = 6
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        let routineModel = store.fetchRoutineModel(id: routine.id)
        guard let routineExercise = routineModel?.exercises?.first else { return routine }
        routineExercise.stallStateValue = StallState(consecutiveMisses: 3, lastWeightKg: 80)
        store.save()
        return routine
    }

    @Test("coachInput reflects the store's own schedule, history and lifts")
    func coachInputReflectsStoreContents() throws {
        let store = try makeStore()
        stalledLift(store, name: "Bench Press")

        let input = store.coachInput()
        #expect(input.workoutDates.count == 1)
        #expect(input.lastWorkoutDate != nil)
        #expect(input.lifts.contains { $0.name == "Bench Press" })
        let lift = input.lifts.first { $0.name == "Bench Press" }
        #expect(lift?.stallState.consecutiveMisses == 3)
        #expect(lift?.lastWorkingWeightKg == 80)
    }

    @Test("an empty store produces no cards — the Coach tab's empty state")
    func emptyStoreProducesNoCards() throws {
        let store = try makeStore()
        #expect(store.coachCards().isEmpty)
    }

    @Test("dismissing a card suppresses it within its cooldown and it returns after")
    func dismissalSuppressesWithinCooldownAndReturnsAfterward() throws {
        let store = try makeStore()
        stalledLift(store, name: "Bench Press")

        let now = Date()
        let before = store.coachCards(now: now)
        let stalled = try #require(before.first { $0.rule == .stalledLift })

        store.recordCoachInteraction(
            rule: stalled.rule, fingerprint: stalled.fingerprint, outcome: .dismissed, date: now
        )
        let stillDismissed = store.coachCards(now: now)
        #expect(!stillDismissed.contains { $0.fingerprint == stalled.fingerprint })

        // Re-fetching interactions from a fresh in-memory read must still suppress it — this is
        // what makes the dismissal survive relaunch, not just this run's in-memory state.
        let reread = store.coachInteractions()
        #expect(reread.contains { $0.fingerprint == stalled.fingerprint && $0.outcome == .dismissed })

        let cooldownDays = CoachRule.stalledLift.cooldownDays
        let afterCooldown = try #require(
            Calendar.current.date(byAdding: .day, value: cooldownDays + 1, to: now)
        )
        let returned = store.coachCards(now: afterCooldown)
        #expect(returned.contains { $0.fingerprint == stalled.fingerprint })
    }

    @Test("approving a deload card applies the suggested weight to the routine's plan")
    func approvingDeloadCardAppliesExpectedChange() throws {
        let store = try makeStore()
        let routine = stalledLift(store, name: "Bench Press")

        let card = try #require(store.coachCards().first { $0.rule == .stalledLift })
        guard case .deloadExercise(let exerciseName, let toWeightKg, _) = card.suggestedAction else {
            Issue.record("expected a deload suggested action")
            return
        }
        #expect(toWeightKg < 80)

        let applied = store.applyCoachDeload(exerciseName: exerciseName, toWeightKg: toWeightKg)
        #expect(applied)

        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        let routineExercise = try #require(routineModel.exercises?.first)
        #expect(routineExercise.plannedSets?.first?.targetWeightKg == toWeightKg)
        #expect(routineExercise.stallStateValue.consecutiveMisses == 0)
        #expect(routineExercise.stallStateValue.lastWeightKg == toWeightKg)
    }
}
