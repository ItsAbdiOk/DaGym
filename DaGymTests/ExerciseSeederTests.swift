import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("ExerciseSeeder")
struct ExerciseSeederTests {
    @Test("seeding is idempotent and produces 1466 exercises with valid muscle raw values")
    func seedsOnceWithValidMuscles() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)

        ExerciseSeeder.seedIfNeeded(context: context)
        let firstCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(firstCount == 1466)

        ExerciseSeeder.seedIfNeeded(context: context)
        let secondCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(secondCount == firstCount)

        let models = try context.fetch(FetchDescriptor<ExerciseModel>())
        for model in models {
            #expect(model.primaryMuscles.allSatisfy { Muscle(rawValue: $0) != nil })
            #expect(model.secondaryMuscles.allSatisfy { Muscle(rawValue: $0) != nil })
        }
    }

    @Test("a bumped seed version refreshes existing rows without duplicating them")
    func bumpedVersionUpdatesExistingRows() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let defaults = UserDefaults(suiteName: #function) ?? .standard
        defaults.removePersistentDomain(forName: #function)

        ExerciseSeeder.seedIfNeeded(context: context, defaults: defaults)
        #expect(defaults.integer(forKey: ExerciseSeeder.seedVersionKey) == 2)

        let benchPress = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        #expect(!benchPress.instructions.isEmpty)
        #expect(benchPress.dataSource == "wger")

        // Re-running with the same stored version must not duplicate rows or
        // re-run the (no-op) update pass.
        ExerciseSeeder.seedIfNeeded(context: context, defaults: defaults)
        let count = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(count == 1466)
    }
}
