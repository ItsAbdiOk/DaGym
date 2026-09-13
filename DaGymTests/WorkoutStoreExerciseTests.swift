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
}
