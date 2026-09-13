import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("ExerciseSeeder")
struct ExerciseSeederTests {
    @Test("seeding is idempotent and produces 692 exercises with valid muscle raw values")
    func seedsOnceWithValidMuscles() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)

        ExerciseSeeder.seedIfNeeded(context: context)
        let firstCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(firstCount == 692)

        ExerciseSeeder.seedIfNeeded(context: context)
        let secondCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(secondCount == firstCount)

        let models = try context.fetch(FetchDescriptor<ExerciseModel>())
        for model in models {
            #expect(model.primaryMuscles.allSatisfy { Muscle(rawValue: $0) != nil })
            #expect(model.secondaryMuscles.allSatisfy { Muscle(rawValue: $0) != nil })
        }
    }
}
