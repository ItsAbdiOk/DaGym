import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("RoutineSeeder")
struct RoutineSeederTests {
    @Test("seeding twice yields exactly 3 starter routines; Push A has 5 exercises and a superset group")
    func seedsStarterRoutinesOnce() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)

        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)

        let routines = store.routines()
        #expect(routines.count == 3)

        let pushA = routines.first { $0.name == "Push A" }
        #expect(pushA?.exercises.count == 5)

        guard let pushAModel = pushA.flatMap({ store.fetchRoutineModel(id: $0.id) }) else {
            Issue.record("Push A routine model not found")
            return
        }
        let supersetGroups = (pushAModel.exercises ?? []).compactMap(\.supersetGroup)
        #expect(!supersetGroups.isEmpty)
    }

    @Test("starter routines carry explicit rules, with overrides where the routine's rule doesn't fit")
    func starterRoutinesHaveRules() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)
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
