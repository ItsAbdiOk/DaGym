import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// OpenGym parity (insights rec 1 + engine rec 5): real starter programs seeded as dedicated
/// routines on demand — `createProgram(from:)` writes exactly its own days into an empty store,
/// reuses a starter the lifter already has and refuses only when a day can't be built —
/// lower-body lifts stepping 5 kg.
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

    @Test("from an empty store a starter program seeds exactly its own routines")
    func programSeedsOnlyItsOwnDays() throws {
        let store = try makeStore(seed: .firstLaunch)
        #expect(store.routines().isEmpty)

        let program = try #require(store.createProgram(from: .upperLower))

        let names = store.routines().map(\.name)
        #expect(Set(names) == ["Upper A", "Lower A", "Upper B", "Lower B"])
        #expect(program.routineIDs.count == 4)
        for name in StarterProgramKind.upperLower.routineNames {
            let model = try routineModel(store, named: name)
            #expect(model.importedFromID == RoutineSeeder.starterIDs[name])
            #expect(program.routineIDs.contains(model.id))
        }
        // A second program adds only what it needs; Push/Pull/Legs shares nothing with it.
        #expect(store.createProgram(from: .pushPullLegs) != nil)
        #expect(store.routines().count == 7)
    }

    @Test("a starter the lifter already has — even renamed — is reused, not seeded again")
    func programReusesExistingStarter() throws {
        let store = try makeStore(seed: .firstLaunch)
        _ = store.createProgram(from: .pushPullLegs)
        let pushA = try routineModel(store, named: "Push A")
        store.saveRoutine(id: pushA.id, name: "Push Day", exercises: [])
        let mine = store.saveRoutine(id: nil, name: "Legs", exercises: [])
        // Drop "Legs" and "Pull B" from the store's starters so the next program must re-seed
        // Pull B, reuse the renamed Push A, and take the lifter's own "Legs" by name.
        let legs = try #require(store.routines().first { $0.name == "Legs" && $0.id != mine.id })
        store.deleteRoutine(id: legs.id)
        let pullB = try routineModel(store, named: "Pull B")
        store.deleteRoutine(id: pullB.id)
        #expect(store.routines().count == 2)

        let program = try #require(store.createProgram(from: .pushPullLegs))

        #expect(program.routineIDs.contains(pushA.id))
        #expect(program.routineIDs.contains(mine.id))
        #expect(store.routines().filter { $0.name == "Push A" }.isEmpty)
        #expect(store.routines().filter { $0.name == "Pull B" }.count == 1)
    }

    @Test("a routine deleted after the program was created is not re-seeded into it")
    func deletedDayIsNotReseeded() throws {
        let store = try makeStore(seed: .firstLaunch)
        let program = try #require(store.createProgram(from: .upperLower))
        let lowerB = try routineModel(store, named: "Lower B")
        store.deleteRoutine(id: lowerB.id)

        let after = try #require(store.programs().first { $0.id == program.id })
        #expect(after.routineIDs.count == 3)
        #expect(!store.routines().contains { $0.name == "Lower B" })
    }

    @Test("a program whose day can't be built refuses: nil, no program inserted")
    func unbuildableDayRefuses() throws {
        // No exercise library: not one starter lift can be looked up.
        let store = try makeStore()
        #expect(store.createProgram(from: .upperLower) == nil)
        #expect(store.programs().isEmpty)
        #expect(store.routines().isEmpty)
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

    @Test("a store that predates the program routines gets nothing on launch — only on demand")
    func launchNeverSeedsProgramRoutines() throws {
        let (store, context) = try makeStoreAndContext(seed: .exercises)
        _ = store.saveRoutine(id: nil, name: "My own day", exercises: [])
        SeedState.row(in: context).routinesSeeded = true
        store.save()

        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        #expect(store.routines().count == 1)

        RoutineSeeder.seedStarters(RoutineSeeder.programRoutineNames, store: store)
        #expect(store.routines().count == 1 + RoutineSeeder.programRoutineNames.count)
        #expect(!store.routines().contains { $0.name == "Push A" })
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
