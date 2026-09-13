import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore change token")
struct ChangeTokenTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(_ store: WorkoutStore) -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8)]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft])
    }

    @Test("finishing a workout bumps the token, so Home's refresh path runs")
    func finishBumps() throws {
        let store = try makeStore()
        let routine = makeRoutine(store)
        let before = store.changeToken

        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        #expect(store.changeToken > before)
    }

    @Test("saving the schedule, a routine and a photo each bump the token; a no-op save doesn't")
    func savesBump() throws {
        let store = try makeStore()
        var token = store.changeToken

        _ = makeRoutine(store)
        #expect(store.changeToken > token)
        token = store.changeToken

        var schedule = WeeklySchedule()
        schedule.days[.monday] = store.routines().first?.id
        store.saveSchedule(schedule)
        #expect(store.changeToken > token)
        token = store.changeToken

        store.save()
        #expect(store.changeToken == token)
    }

    @Test("the snapshot Home renders changes with the token after a finish")
    func homeSnapshotFollowsToken() throws {
        let store = try makeStore()
        let suite = UserDefaults(suiteName: #function) ?? .standard
        suite.removePersistentDomain(forName: #function)
        let preferences = Preferences(suite: suite)
        let routine = makeRoutine(store)

        let idle = HomeSnapshot.make(store: store, preferences: preferences)
        let token = store.changeToken
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        #expect(store.changeToken != token)
        let refreshed = HomeSnapshot.make(store: store, preferences: preferences)
        #expect(refreshed.thisWeekCount == idle.thisWeekCount + 1)
    }
}
