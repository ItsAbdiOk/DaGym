import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("RoutineSeeder")
struct RoutineSeederTests {
    @Test("seeding twice yields the 13 starter routines once; Push A has 5 exercises and a superset group")
    func seedsStarterRoutinesOnce() throws {
        let store = try makeStore(seed: .exercises)

        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)

        let routines = store.routines()
        #expect(routines.count == 13)

        let pushA = routines.first { $0.name == "Push A" }
        #expect(pushA?.exercises.count == 5)

        guard let pushAModel = pushA.flatMap({ store.fetchRoutineModel(id: $0.id) }) else {
            Issue.record("Push A routine model not found")
            return
        }
        let supersetGroups = (pushAModel.exercises ?? []).compactMap(\.supersetGroup)
        #expect(!supersetGroups.isEmpty)
    }

    /// Pins the first-launch cost: every one of the ~50 slot lookups used to re-fetch the whole
    /// library (and the PR cache) and re-fold every row's search text — 2.9 s on the main thread
    /// of a fresh install, measured with Time Profiler on an iPhone 16 Pro in Low Power Mode.
    /// Query count, not wall-clock: the library and PR cache must be read once for the whole seed.
    @Test("a first-launch seed reads the exercise library once, not once per slot")
    func firstLaunchSeedReadsTheLibraryOnce() throws {
        let store = try makeStore(seed: .exercises)

        let before = store.queryCount
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let queries = store.queryCount - before

        #expect(store.routines().count == 13)
        // Exactly: the routine list, the two catalogue reads (library, PR cache) and the
        // per-routine bookkeeping `saveRoutine` and `stamp` do for the 13 routines. The old shape
        // was 182 for the same store — two per slot lookup, three when a fallback fired. Exact,
        // not a ceiling: a new query on the first-launch path should be a deliberate change.
        // Still 72 after the routine fold moved out of this seeder: `dedupeRoutines()` now
        // reads through `fetch()` (counted), so a `defer` that folded here would show up as 73+.
        #expect(queries == 72, "seeding the starter routines issued \(queries) queries")
    }

    @Test("starter routines carry explicit rules, with overrides where the routine's rule doesn't fit")
    func starterRoutinesHaveRules() throws {
        let store = try makeStore(seed: .exercises)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)

        let routines = store.routines()
        let legs = try #require(
            routines.first { $0.name == "Legs" }.flatMap { store.fetchRoutineModel(id: $0.id) }
        )
        #expect(legs.progressionRuleValue == .linear(incrementKg: 2.5))
        let byName = Dictionary(
            uniqueKeysWithValues: (legs.exercises ?? []).compactMap { model in
                model.exercise.map { ($0.name, model.overrideRuleValue) }
            }
        )
        // A 5 kg lower-body lift keeps the routine's linear shape with its own increment; a
        // hold goes by seconds.
        #expect(byName["Barbell Squat"] == .linear(incrementKg: 5))
        #expect(byName["Plank"] == .timed(stepSeconds: TrainingConstants.defaultTimedStepSeconds))

        let pushA = try #require(
            routines.first { $0.name == "Push A" }.flatMap { store.fetchRoutineModel(id: $0.id) }
        )
        #expect(pushA.progressionRuleValue == .doubleProgression(low: 6, high: 8, incrementKg: 2.5))
        let incline = (pushA.exercises ?? []).first { $0.exercise?.name == "Incline Dumbbell Press" }
        #expect(incline?.overrideRuleValue == .doubleProgression(low: 6, high: 8, incrementKg: 2))
    }
}
