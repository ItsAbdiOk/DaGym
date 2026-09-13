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
}
