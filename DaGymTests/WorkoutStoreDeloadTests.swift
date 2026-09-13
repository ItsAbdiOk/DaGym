import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore deload suggestion")
struct WorkoutStoreDeloadTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    /// A routine with one main-lift exercise, a finished session for history, and a stalled
    /// `RoutineExerciseModel` (3 consecutive misses) — the shape `deloadSuggestion` needs.
    private func stalledLift(_ store: WorkoutStore, name: String) {
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
        guard let routineExercise = routineModel?.exercises?.first else { return }
        routineExercise.stallStateValue = StallState(consecutiveMisses: 3, lastWeightKg: 80)
        store.save()
    }

    @Test("a deload suggestion appears with 3 stalls on 2 main lifts")
    func suggestionAppearsWithTwoStalledLifts() throws {
        let store = try makeStore()
        stalledLift(store, name: "Bench Press")
        stalledLift(store, name: "Squat")

        let suggestion = store.deloadSuggestion(snoozedUntil: nil)
        #expect(suggestion != nil)
        #expect(suggestion?.reason.contains("Bench") == true || suggestion?.reason.contains("Squat") == true)
    }

    @Test("only one stalled lift doesn't warrant a suggestion")
    func oneStalledLiftIsNotEnough() throws {
        let store = try makeStore()
        stalledLift(store, name: "Bench Press")

        #expect(store.deloadSuggestion(snoozedUntil: nil) == nil)
    }

    @Test("snoozing hides the suggestion until the snooze date passes")
    func snoozeHidesSuggestion() throws {
        let store = try makeStore()
        stalledLift(store, name: "Bench Press")
        stalledLift(store, name: "Squat")

        let future = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        #expect(store.deloadSuggestion(snoozedUntil: future) == nil)

        let past = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        #expect(store.deloadSuggestion(snoozedUntil: past) != nil)
    }

    @Test("a genuine e1RM decline (no planned deload) does fire the trend reason")
    func genuineDeclineTriggersTrend() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 100)]
        )
        let routine = store.saveRoutine(
            id: nil, name: "Bench Press", rule: .linear(incrementKg: 2.5), exercises: [draft]
        )

        // Same two-step decline as `plannedDeloadSessionExcludedFromTrend` below, but nothing is
        // flagged as a planned deload — this must be the positive case the exclusion test is
        // actually excluding, or a broken `mainLiftKey` match would make both tests pass vacuously.
        logDeloadable(store, routineID: routine.id, weightKg: 110, reps: 5, wasPlannedDeload: false)
        logDeloadable(store, routineID: routine.id, weightKg: 100, reps: 5, wasPlannedDeload: false)
        logDeloadable(store, routineID: routine.id, weightKg: 85, reps: 5, wasPlannedDeload: false)

        let suggestion = try #require(store.deloadSuggestion(snoozedUntil: nil))
        #expect(suggestion.reason.contains("e1RM is down"))
    }

    @Test("a planned deload session's lower numbers never read as an e1RM decline")
    func plannedDeloadSessionExcludedFromTrend() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 100)]
        )
        let routine = store.saveRoutine(
            id: nil, name: "Bench Press", rule: .linear(incrementKg: 2.5), exercises: [draft]
        )

        // A genuine two-step decline (110 → 100 → 85) that would otherwise fire the trend
        // reason (proven by `genuineDeclineTriggersTrend` above) — but the last point is a
        // planned deload at -15%, which must never count.
        logDeloadable(store, routineID: routine.id, weightKg: 110, reps: 5, wasPlannedDeload: false)
        logDeloadable(store, routineID: routine.id, weightKg: 100, reps: 5, wasPlannedDeload: false)
        logDeloadable(store, routineID: routine.id, weightKg: 85, reps: 5, wasPlannedDeload: true)

        let suggestion = store.deloadSuggestion(snoozedUntil: nil)
        #expect(suggestion?.reason.contains("e1RM is down") != true)
    }

    @Test("dismissing a suggestion suppresses that exact evidence but not new evidence")
    func dismissedFingerprintSuppressesSameEvidenceOnly() throws {
        let store = try makeStore()
        stalledLift(store, name: "Bench Press")
        stalledLift(store, name: "Squat")

        let suggestion = try #require(store.deloadSuggestion(snoozedUntil: nil))
        let dismissed = store.deloadSuggestion(
            snoozedUntil: nil, dismissedFingerprint: suggestion.fingerprint
        )
        #expect(dismissed == nil)

        stalledLift(store, name: "Overhead Press")
        let stillSuppressed = store.deloadSuggestion(
            snoozedUntil: nil, dismissedFingerprint: suggestion.fingerprint
        )
        // New evidence (a third stalled lift changes the reason string/fingerprint) still shows.
        #expect(stillSuppressed != nil)
        #expect(stillSuppressed?.fingerprint != suggestion.fingerprint)
    }

    /// Like `stalledLift`'s session logging, but lets the caller flag the session as a planned
    /// deload and choose the load, for trend-exclusion tests.
    private func logDeloadable(
        _ store: WorkoutStore, routineID: UUID, weightKg: Double, reps: Int, wasPlannedDeload: Bool
    ) {
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].weightKg = weightKg
        session.exercises[0].sets[0].reps = reps
        session.exercises[0].sets[0].isDone = true
        session.exercises[0].wasPlannedDeload = wasPlannedDeload
        _ = store.finish(session: session)
    }
}
