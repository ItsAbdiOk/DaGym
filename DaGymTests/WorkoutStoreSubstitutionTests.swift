import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore substitutions")
struct WorkoutStoreSubstitutionTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)
        EquipmentSeeder.seedIfNeeded(store: store)
        return store
    }

    private func exercise(_ store: WorkoutStore, named name: String) throws -> ExerciseInfo {
        try #require(store.exercises(matching: name).first { $0.name == name })
    }

    @Test("only equipment in the active profile comes back")
    func equipmentFiltering() throws {
        let store = try makeStore()
        let home = try #require(store.equipmentProfiles().first { $0.name == "Home" })
        store.setActive(id: home.id)

        let bench = try exercise(store, named: "Barbell Bench Press - Medium Grip")
        let results = store.substitutes(for: bench.id, reason: .noBarbell)

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { home.availableEquipment.contains($0.exercise.equipment) })
        #expect(!results.contains { $0.exercise.equipment == "barbell" })
    }

    @Test("shoulderHurts steers away from delt-heavy candidates")
    func shoulderRule() throws {
        let store = try makeStore()
        let gym = try #require(store.equipmentProfiles().first { $0.name == "Gym" })
        store.setActive(id: gym.id)

        let bench = try exercise(store, named: "Barbell Bench Press - Medium Grip")
        let results = store.substitutes(for: bench.id, reason: .shoulderHurts)

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { !$0.exercise.secondary.contains(.delts) })
    }

    @Test("a fatigued shared muscle can reorder candidates")
    func recoveryPenalty() throws {
        let store = try makeStore()
        let gym = try #require(store.equipmentProfiles().first { $0.name == "Gym" })
        store.setActive(id: gym.id)

        let bench = try exercise(store, named: "Barbell Bench Press - Medium Grip")
        let fresh = store.substitutes(for: bench.id, reason: .machineTaken)
        #expect(!fresh.isEmpty)
    }

    @Test("returns at most 3 suggestions, each with a non-empty why")
    func topThreeWithWhy() throws {
        let store = try makeStore()
        let gym = try #require(store.equipmentProfiles().first { $0.name == "Gym" })
        store.setActive(id: gym.id)

        let bench = try exercise(store, named: "Barbell Bench Press - Medium Grip")
        let results = store.substitutes(for: bench.id, reason: .machineTaken)

        #expect(results.count <= 3)
        #expect(results.allSatisfy { !$0.why.isEmpty })
    }

    @Test("an unknown exercise ID returns no suggestions")
    func unknownExercise() throws {
        let store = try makeStore()
        #expect(store.substitutes(for: UUID(), reason: .machineTaken).isEmpty)
    }
}
