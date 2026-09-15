import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Runs each App Intent's `perform()` the way Siri would, against an in-memory store handed in
/// through `IntentStoreAccess.testOverride` — without it every intent answers "isn't available"
/// in a test host, since `LaunchFlags.isTesting` hides the real container.
@MainActor
@Suite("App Intents perform", .serialized)
struct IntentPerformTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func install(_ name: String) throws -> (store: WorkoutStore, preferences: Preferences) {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))
        let preferences = Preferences(suite: makeSuite(name + "prefs"))
        IntentStoreAccess.testOverride = (store, preferences)
        return (store, preferences)
    }

    private func finishWorkout(_ store: WorkoutStore, daysAgo: Int) {
        let date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        let session = store.startBackfill(date: date, durationMinutes: 45, routineID: nil)
        _ = store.finish(session: session)
    }

    @Test("logging bodyweight in pounds stores kilograms")
    func logBodyweightInPounds() async throws {
        let (store, preferences) = try install(#function)
        defer { IntentStoreAccess.testOverride = nil }
        preferences.weightUnit = .lb
        let intent = LogBodyweightIntent()
        intent.weight = 176

        _ = try await intent.perform()

        let logged = try #require(store.latestBodyMeasurement())
        let kg = try #require(logged.bodyweightKg)
        #expect(abs(kg - WeightUnit.lb.toKg(176)) < 0.01)
        #expect(logged.source == "manual")
        let dialog = IntentFormatting.bodyweightLoggedDialog(kg: kg, unit: .lb)
        #expect(dialog == "Logged 176 lb.")
    }

    @Test("a zero or negative bodyweight is asked for again, not stored")
    func rejectsNonPositiveBodyweight() async throws {
        let (store, _) = try install(#function)
        defer { IntentStoreAccess.testOverride = nil }
        let intent = LogBodyweightIntent()
        intent.weight = 0

        await #expect(throws: (any Error).self) { _ = try await intent.perform() }
        #expect(store.latestBodyMeasurement() == nil)
    }

    @Test("the streak intent reports Home's numbers in the user's own week")
    func streakFromStore() async throws {
        let (store, preferences) = try install(#function)
        defer { IntentStoreAccess.testOverride = nil }
        preferences.weeklyGoal = 1
        finishWorkout(store, daysAgo: 0)
        finishWorkout(store, daysAgo: 7)

        let streak = GetStreakIntent.streak(store: store, preferences: preferences)
        _ = try await GetStreakIntent().perform()

        #expect(streak.current == 2)
        #expect(streak.thisWeekCount == 1)
        #expect(streak.weeklyGoal == 1)
        #expect(
            IntentFormatting.streakDialog(current: 2, thisWeekCount: 1, weeklyGoal: 1)
                == "You're on a 2-week streak, with 1 of 1 workout this week."
        )
        #expect(
            IntentFormatting.streakDialog(current: 0, thisWeekCount: 2, weeklyGoal: 4)
                == "No streak yet — 2 of 4 workouts this week. Hit your goal to start one."
        )
    }

    @Test("starting a workout queues the hand-off and names today's routine")
    func startWorkoutQueuesAndNames() async throws {
        let (store, _) = try install(#function)
        defer { IntentStoreAccess.testOverride = nil }
        _ = PendingIntentHandoff.consume(routineLoaded: true)
        let exercise = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: [PlannedSetDraft(kind: .working)])
        _ = store.saveRoutine(id: nil, name: "Push A", exercises: [draft])

        _ = try await StartWorkoutIntent().perform()

        #expect(PendingIntentHandoff.consume(routineLoaded: true) == [.startWorkout])
        #expect(StartWorkoutIntent.dialog() == "Starting Push A.")
        // A rest day starts a freestyle session for real (`RootView.startPendingWorkout`), so
        // the dialog may promise one.
        #expect(IntentFormatting.startWorkoutDialog(routineName: nil) == "Starting a freestyle workout.")
    }

    @Test("with a session already in progress the dialog says it is continued, not started")
    func startWorkoutContinuesUnfinished() async throws {
        let (store, _) = try install(#function)
        defer { IntentStoreAccess.testOverride = nil }
        _ = PendingIntentHandoff.consume(routineLoaded: true)
        let exercise = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: [PlannedSetDraft(kind: .working)])
        let routine = store.saveRoutine(id: nil, name: "Push A", exercises: [draft])
        let live = store.startWorkout(routineID: routine.id)
        store.sync(session: live)

        _ = try await StartWorkoutIntent().perform()

        #expect(PendingIntentHandoff.consume(routineLoaded: true) == [.startWorkout])
        #expect(StartWorkoutIntent.dialog() == "Continuing Push A.")
        #expect(IntentFormatting.continueWorkoutDialog(title: "Legs") == "Continuing Legs.")
    }

    @Test("the rest timer intent queues its hand-off without needing a store")
    func restTimerQueues() async throws {
        IntentStoreAccess.testOverride = nil
        _ = PendingIntentHandoff.consume(routineLoaded: true)

        _ = try await StartRestTimerIntent().perform()

        #expect(PendingIntentHandoff.consume(routineLoaded: true) == [.startRestTimer])
    }

    @Test("without the override a test host gets no store, so background intents decline safely")
    func noStoreWithoutOverride() async throws {
        IntentStoreAccess.testOverride = nil
        #expect(IntentStoreAccess.makeStore() == nil)
        _ = try await GetStreakIntent().perform()
        #expect(StartWorkoutIntent.dialog() == "Starting your workout.")
    }
}
