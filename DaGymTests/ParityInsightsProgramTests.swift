import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// OpenGym parity (insights rec 1 + engine rec 5): real starter programs seeded as dedicated
/// routines, `createProgram(from:)` refusing when one is missing, lower-body lifts stepping 5 kg.
@MainActor
@Suite("Parity: starter programs")
struct ParityInsightsProgramTests {
    private func routineModel(_ store: WorkoutStore, named name: String) throws -> RoutineModel {
        let info = try #require(store.routines().first { $0.name == name })
        return try #require(store.fetchRoutineModel(id: info.id))
    }

    @Test("5×5 cycles three routines, each exactly 3 exercises × 5 sets × 5 reps on a linear rule")
    func fiveByFiveShape() throws {
        let store = try makeStore(seed: [.exercises, .routines])
        let program = try #require(store.createProgram(from: .fiveByFive))
        #expect(program.routineIDs.count == 3)
        #expect(Set(program.routineIDs).count == 3)
        for routineID in program.routineIDs {
            let model = try #require(store.fetchRoutineModel(id: routineID))
            #expect(model.progressionRuleValue == .linear(incrementKg: 2.5))
            let exercises = (model.exercises ?? []).sorted { $0.order < $1.order }
            #expect(exercises.count == 3)
            for exercise in exercises {
                let sets = exercise.plannedSets ?? []
                #expect(sets.count == 5)
                #expect(sets.allSatisfy { $0.setKind == .working && $0.targetReps == 5 })
            }
        }
    }

    @Test("Upper/Lower cycles 4 distinct routines, none of them Push A")
    func upperLowerIsDedicated() throws {
        let store = try makeStore(seed: [.exercises, .routines])
        let program = try #require(store.createProgram(from: .upperLower))
        #expect(program.routineIDs.count == 4)
        #expect(Set(program.routineIDs).count == 4)
        let routines = store.routines()
        let names = program.routineIDs.compactMap { id in routines.first { $0.id == id }?.name }
        #expect(names == ["Upper A", "Lower A", "Upper B", "Lower B"])
        #expect(!names.contains("Push A"))
        #expect(store.routines().contains { $0.name == "Push A" })
    }

    @Test("Full Body cycles 3 distinct routines")
    func fullBodyIsDedicated() throws {
        let store = try makeStore(seed: [.exercises, .routines])
        let program = try #require(store.createProgram(from: .fullBody))
        #expect(Set(program.routineIDs).count == 3)
    }

    @Test("deleting Lower B makes Upper/Lower refuse: nil, no program inserted")
    func missingRoutineRefuses() throws {
        let store = try makeStore(seed: [.exercises, .routines])
        let lowerB = try #require(store.routines().first { $0.name == "Lower B" })
        store.deleteRoutine(id: lowerB.id)

        #expect(store.createProgram(from: .upperLower) == nil)
        #expect(store.programs().isEmpty)
        // The other programs are untouched.
        #expect(store.createProgram(from: .pushPullLegs) != nil)
    }

    @Test("seeded starter ids are stable and unique per routine")
    func starterIDsStable() {
        #expect(RoutineSeeder.starterIDs["Push A"]?.uuidString == "6D1A5D4E-0001-4A00-8000-000000000001")
        #expect(RoutineSeeder.starterIDs["Legs"]?.uuidString == "6D1A5D4E-0003-4A00-8000-000000000003")
        #expect(Set(RoutineSeeder.starterIDs.values).count == RoutineSeeder.starterIDs.count)
        for name in RoutineSeeder.programRoutineNames {
            #expect(RoutineSeeder.starterIDs[name] != nil)
        }
    }

    @Test("a store seeded before the program routines existed gets them once; deleting one sticks")
    func upgradeSeedsProgramRoutinesOnce() throws {
        let (store, context) = try makeStoreAndContext(seed: .exercises)
        _ = store.saveRoutine(id: nil, name: "My own day", exercises: [])
        SeedState.row(in: context).routinesSeeded = true
        store.save()

        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        #expect(store.routines().count == 1 + RoutineSeeder.programRoutineNames.count)
        #expect(!store.routines().contains { $0.name == "Push A" })

        let lowerB = try #require(store.routines().first { $0.name == "Lower B" })
        store.deleteRoutine(id: lowerB.id)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        #expect(!store.routines().contains { $0.name == "Lower B" })
    }

    @Test("seeded squat steps 5 kg, seeded bench 2.5 kg (engine rec 5, seeder half)")
    func lowerBodyIncrement() throws {
        let store = try makeStore(seed: [.exercises, .routines])
        let fiveByFiveA = try routineModel(store, named: "5×5 A")
        let routineRule = fiveByFiveA.progressionRuleValue
        let byName = Dictionary(
            uniqueKeysWithValues: (fiveByFiveA.exercises ?? []).compactMap { model in
                model.exercise.map { ($0.name, model.overrideRuleValue ?? routineRule) }
            }
        )
        let lowerStep = TrainingConstants.defaultLowerBodyIncrementKg
        #expect(byName["Barbell Squat"] == .linear(incrementKg: lowerStep))
        #expect(byName["Barbell Bench Press - Medium Grip"] == .linear(incrementKg: 2.5))

        // A lower-body machine whose library increment is 2.5 still seeds with the lower-body step.
        let lowerA = try routineModel(store, named: "Lower A")
        let legPress = try #require((lowerA.exercises ?? []).first { $0.exercise?.name == "Leg Press" })
        #expect(legPress.overrideRuleValue == .linear(incrementKg: lowerStep))
    }

    @Test("starterIncrementKg: lower-body primary → 5 kg, otherwise the library increment")
    func starterIncrementHelper() {
        let store = (try? makeStore(seed: [.exercises, .routines]))
        let squat = store?.exercises(matching: "Barbell Squat").first { $0.name == "Barbell Squat" }
        let curl = store?.exercises(matching: "Dumbbell Bicep Curl")
            .first { $0.name == "Dumbbell Bicep Curl" }
        let lowerStep = TrainingConstants.defaultLowerBodyIncrementKg
        #expect(squat.map(RoutineSeeder.starterIncrementKg) == lowerStep)
        #expect(curl.map(RoutineSeeder.starterIncrementKg) == curl?.incrementKg)
        #expect((curl?.incrementKg ?? 0) < TrainingConstants.defaultLowerBodyIncrementKg)
    }
}
