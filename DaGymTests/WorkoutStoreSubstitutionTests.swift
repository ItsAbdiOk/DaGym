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

    /// A store with one active equipment profile and nothing else seeded — no 1466-exercise
    /// library to compete with the two hand-built candidates `recoveryPenalty` needs to reorder.
    private func makeUnseededStore(availableEquipment: [String]) throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        context.insert(
            EquipmentProfileModel(name: "Test", isActive: true, availableEquipment: availableEquipment)
        )
        try context.save()
        return WorkoutStore(context: context)
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

    @Test("a fatigued shared muscle reorders candidates, not just returns some")
    func recoveryPenalty() throws {
        let store = try makeUnseededStore(availableEquipment: ["dumbbell"])

        let subject = store.createCustomExercise(
            name: "ZZZ Subject Press", primary: [.chest, .triceps], equipment: "dumbbell", style: .weightReps
        )
        let chestOnly = store.createCustomExercise(
            name: "AAA Chest Only Fly", primary: [.chest], equipment: "dumbbell", style: .weightReps
        )
        let tricepsOnly = store.createCustomExercise(
            name: "BBB Triceps Only Extension", primary: [.triceps], equipment: "dumbbell", style: .weightReps
        )

        // Baseline: neither candidate has been trained, so both score equal (one shared primary
        // muscle, same equipment/mechanic) and the alphabetical tiebreak orders "AAA…" first.
        let baseline = store.substitutes(for: subject.id, reason: .machineTaken).map(\.exercise.name)
        #expect(baseline == [chestOnly.name, tricepsOnly.name])

        // Fatigue chest well past Substitutions' 0.6-spent penalty threshold (12 all-out sets;
        // 3 all-out sets alone only reaches ~0.33, per WorkoutStoreRecoverySnapshotTests) by
        // logging on the chest-only exercise itself — triceps stays completely fresh.
        let sets = (0..<12).map { _ in PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 20) }
        let draft = RoutineExerciseDraft(exerciseID: chestOnly.id, sets: sets)
        let routineID = store.saveRoutine(id: nil, name: "Fatigue Chest", exercises: [draft]).id
        let session = store.startWorkout(routineID: routineID)
        for index in 0..<12 {
            session.exercises[0].sets[index].weightKg = 20
            session.exercises[0].sets[index].reps = 5
            session.exercises[0].sets[index].effort = Effort(rpe: 10)
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)

        let afterFatigue = store.substitutes(for: subject.id, reason: .machineTaken).map(\.exercise.name)
        // The chest-only candidate now carries a fatigue penalty the triceps-only one doesn't —
        // the ranking must flip, proving the recovery map actually reorders results.
        #expect(afterFatigue == [tricepsOnly.name, chestOnly.name])
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
