import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// The wrist runs the phone's own `WorkoutStore`, so a session started on the watch must carry
/// exactly the prescription the phone would show for the same store, and a workout finished on
/// the watch must land in SwiftData the way the phone's does — with the device stamped, the
/// progression judgement committed and the PR cache updated.
@MainActor
@Suite("WatchStore parity with the phone")
struct WatchStoreParityTests {
    /// One seeded in-memory container, both stores on its main context. The container is kept
    /// too: a `ModelContext` only weakly references it, and a fetch on a context whose container
    /// has been released traps inside SwiftData.
    private struct Fixture {
        let phone: WorkoutStore
        let watch: WatchStore
        let container: ModelContainer
    }

    private func makeStores() throws -> Fixture {
        let container = try ModelContainer.dagym(inMemory: true)
        let phone = WorkoutStore(context: container.mainContext, photoContext: nil)
        WatchSampleSeeder.seed(store: phone)
        let watch = WatchStore(
            store: WorkoutStore(context: container.mainContext, photoContext: nil),
            preferences: WatchPreferences(defaults: WatchTestDefaults.fresh()),
            runtime: WatchWorkoutRuntime(isEnabled: false)
        )
        watch.refreshHome()
        return Fixture(phone: phone, watch: watch, container: container)
    }

    private func targets(_ session: WorkoutSession) -> [[String]] {
        session.exercises.map { entry in
            entry.sets.map { "\($0.kind.rawValue) \($0.weightKg)×\($0.reps) \($0.targetSeconds ?? 0)" }
        }
    }

    @Test("today's entries carry the prescription the phone gives the same store")
    func prescriptionParity() throws {
        let fixture = try makeStores()
        let (phone, watch) = (fixture.phone, fixture.watch)
        let routine = try #require(phone.todaysRoutine())
        let phoneSession = phone.startWorkout(routineIDs: [routine.id])
        let expected = targets(phoneSession)
        phone.discard(session: phoneSession)

        watch.start(routineID: routine.id)
        let session = try #require(watch.session)

        #expect(targets(session) == expected)
        // The seeded history has bench at 97.5 × 5, so the linear rule prescribes 100 today —
        // proof the comparison is of a real prescription, not two empty plans.
        // The seeded history is bench at 97.5 × 5 and the plan names 100 on its first set: the
        // built entries carry both (the store's own auto-fill and plan-override rules), which
        // is what makes the comparison a real one and not two empty plans.
        let bench = try #require(session.exercises.first)
        let working = bench.sets.filter { $0.kind.countsTowardStats }
        #expect(working.map(\.weightKg) == [100, 97.5, 97.5, 97.5])
        #expect(bench.sets.contains { $0.kind == .warmup })
        #expect(watch.amrapTargets.values.contains(6))
        withExtendedLifetime(fixture) {}
    }

    @Test("finishing on the watch persists the workout with the device, progression and PRs")
    func finishPersists() throws {
        let fixture = try makeStores()
        let (phone, watch) = (fixture.phone, fixture.watch)
        let routine = try #require(phone.todaysRoutine())
        watch.start(routineID: routine.id)
        let session = try #require(watch.session)
        let bench = try #require(session.exercises.first)
        let workoutID = try #require(session.workoutID)

        // Every warm-up and straight set at 100, then the AMRAP at 100 × 7 — over the 5-rep
        // target, which both moves the linear rule on and beats the seeded 97.5 × 6 e1RM.
        var logged = 0
        while let set = session.exercises[0].sets.first(where: { !$0.isDone }) {
            watch.updateSet(exerciseID: bench.id) { $0.weightKg = 100; $0.reps = set.kind == .amrap ? 7 : 5 }
            watch.logCurrentSet(exerciseID: bench.id)
            watch.skipRest()
            logged += 1
        }
        watch.finish()

        #expect(watch.session == nil)
        #expect((watch.summary?.setsDone ?? 0) >= 4)
        let workout = try #require(phone.workout(id: workoutID))
        #expect(workout.sourceDevice == "Apple Watch")
        #expect(workout.endedAt != nil)
        let benchRows = try #require(workout.exercises?.first { $0.exercise?.name == "Bench Press" })
        let rows = (benchRows.sets ?? []).filter(\.isCompleted).sorted { $0.order < $1.order }
        #expect(rows.count == logged)
        #expect(rows.last?.weightKg == 100)
        #expect(rows.last?.reps == 7)
        #expect(rows.last?.kind == "amrap")

        // Progression committed: the next session prescribes the increment.
        let next = phone.startWorkout(routineIDs: [routine.id])
        let nextBench = try #require(next.exercises.first)
        #expect(nextBench.sets.filter { $0.kind == .working }.allSatisfy { $0.weightKg == 102.5 })

        // PR cache: the e1RM record for the bench is now the 100 × 7 from this workout.
        let records = phone.fetch(FetchDescriptor<PersonalRecordModel>())
            .filter { $0.kind == "e1rm" && $0.workoutID == workoutID }
        #expect(records.contains { $0.weightKg == 100 && $0.reps == 7 })
        #expect(watch.preferences.lastSavedAt != nil)
        withExtendedLifetime(fixture) {}
    }
}

/// A throwaway `UserDefaults` suite per test, so preferences never leak between them.
enum WatchTestDefaults {
    static func fresh() -> UserDefaults {
        let name = "watch-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
