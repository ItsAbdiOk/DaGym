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

    @Test("a bumped seed version refreshes an existing row's stale instructions and provenance")
    func bumpedVersionUpdatesExistingRows() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        // Seed once at version 0 (nothing applied yet), then hand-corrupt one row the way an
        // older seed version would have left it — stale instructions and a placeholder source —
        // so the update pass this test actually exercises has something to fix.
        ExerciseSeeder.seedIfNeeded(context: context)
        let seededCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        let staleBenchPress = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        staleBenchPress.instructions = "stale placeholder instructions"
        staleBenchPress.dataSource = "stale-source"
        SeedState.row(in: context).exerciseSeedVersion = 0
        try context.save()

        // Now seed again as if the bundled seed bumped to version 3 (its real value) — this must
        // refresh the stale row in place, not skip it because `insertMissing` already saw the ID.
        ExerciseSeeder.seedIfNeeded(context: context)
        #expect(SeedState.row(in: context).exerciseSeedVersion == 3)

        let benchPress = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        #expect(benchPress.instructions != "stale placeholder instructions")
        #expect(!benchPress.instructions.isEmpty)
        #expect(benchPress.dataSource == "wger")

        // Re-running with the same stored version must not duplicate rows or
        // re-run the (no-op) update pass.
        ExerciseSeeder.seedIfNeeded(context: context)
        let count = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(count == seededCount)
        #expect(count == 1466)
    }

    @Test("every seeded exercise has non-empty instructions within a sane length")
    func everyExerciseHasInstructions() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)

        ExerciseSeeder.seedIfNeeded(context: context)
        let models = try context.fetch(FetchDescriptor<ExerciseModel>())
        let total = models.count

        let nonEmptyCount = models.filter { !$0.instructions.isEmpty }.count
        #expect(nonEmptyCount == total)

        // Our own text is capped; wger text is kept verbatim (CC-BY-SA) and may run longer.
        for model in models where model.dataSource != "wger" {
            let wordCount = model.instructions.split(separator: " ").count
            #expect(
                wordCount <= 90,
                "\(model.seedID ?? model.name) has \(wordCount) words"
            )
        }
    }
}
