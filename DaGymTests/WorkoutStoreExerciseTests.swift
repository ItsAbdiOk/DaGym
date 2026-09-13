import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore exercises")
struct WorkoutStoreExerciseTests {
    @Test("custom exercise round trip and favorites sort first")
    func customExerciseRoundTrip() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

        let created = store.createCustomExercise(
            name: "Zercher Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        #expect(created.isCustom)
        #expect(created.name == "Zercher Squat")

        context.insert(ExerciseModel(name: "Alpha Curl"))
        context.insert(ExerciseModel(name: "Beta Row"))
        try context.save()

        store.toggleFavorite(id: created.id)
        let results = store.exercises(matching: "")
        #expect(results.first?.id == created.id)

        let favoriteNames = results.prefix(while: \.isFavorite).map(\.name)
        #expect(favoriteNames == ["Zercher Squat"])
    }

    @Test("updateExerciseSettings writes rest, bar type and increment back to the model")
    func updateExerciseSettings() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

        let created = store.createCustomExercise(
            name: "Incline Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        #expect(created.restSeconds == 150)

        store.updateExerciseSettings(id: created.id, restSeconds: 120, barType: "ezBar", incrementKg: 1.25)

        let model = store.fetchExerciseModel(id: created.id)
        #expect(model?.restSeconds == 120)
        #expect(model?.barType == "ezBar")
        #expect(model?.incrementKg == 1.25)

        let refreshed = store.exercises(matching: "Incline Press").first
        #expect(refreshed?.restSeconds == 120)
        #expect(refreshed?.incrementKg == 1.25)
    }
}
