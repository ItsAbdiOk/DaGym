import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Seed state and dedupe")
struct SeedDedupeTests {
    private func seededStore() throws -> (store: WorkoutStore, context: ModelContext) {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        EquipmentSeeder.seedIfNeeded(store: store)
        return (store, context)
    }

    /// What a second iCloud device's first launch produces once its rows sync in: every seeded
    /// exercise again under a new `id`, the same `seedID`s, and a starter routine pointing at
    /// its own copies.
    private func simulateRemoteImport(into context: ModelContext) throws -> UUID {
        let existing = try context.fetch(FetchDescriptor<ExerciseModel>())
        var copies: [String: ExerciseModel] = [:]
        for model in existing {
            guard let seedID = model.seedID else { continue }
            let copy = ExerciseModel(
                seedID: seedID, name: model.name, primaryMuscles: model.primaryMuscles,
                equipment: model.equipment, loggingStyle: model.loggingStyle,
                createdAt: model.createdAt.addingTimeInterval(60)
            )
            context.insert(copy)
            copies[seedID] = copy
        }
        let remoteRoutine = RoutineModel(
            name: "Push A", createdAt: Date().addingTimeInterval(60),
            updatedAt: Date().addingTimeInterval(60), importedFromID: RoutineSeeder.starterIDs["Push A"]
        )
        context.insert(remoteRoutine)
        let bench = try #require(copies["Barbell_Bench_Press_-_Medium_Grip"])
        let slot = RoutineExerciseModel(order: 0, exercise: bench, routine: remoteRoutine)
        context.insert(slot)
        remoteRoutine.exercises = [slot]
        try context.save()
        return remoteRoutine.id
    }

    @Test("a remote copy of every seeded row folds into one survivor per seedID with slots re-pointed")
    func remoteImportFoldsToOneSurvivorPerSeedID() throws {
        let (store, context) = try seededStore()
        let survivorIDs = Set(try context.fetch(FetchDescriptor<ExerciseModel>()).map(\.id))
        let remoteRoutineID = try simulateRemoteImport(into: context)
        #expect(try context.fetch(FetchDescriptor<ExerciseModel>()).count == survivorIDs.count * 2)

        let folded = store.dedupeSeededRows()
        #expect(folded == survivorIDs.count + 1)

        let exercises = try context.fetch(FetchDescriptor<ExerciseModel>())
        #expect(exercises.count == survivorIDs.count)
        #expect(Set(exercises.compactMap(\.seedID)).count == exercises.count)
        #expect(Set(exercises.map(\.id)) == survivorIDs)

        let routines = try context.fetch(FetchDescriptor<RoutineModel>())
        #expect(routines.count == 3)
        #expect(routines.filter { $0.name == "Push A" }.count == 1)
        for slot in routines.flatMap({ $0.exercises ?? [] }) {
            let exerciseID = try #require(slot.exercise?.id)
            #expect(survivorIDs.contains(exerciseID))
        }
        // The remote routine was newer, so it survived; its slot now points at the original bench.
        let pushA = try #require(routines.first { $0.name == "Push A" })
        #expect(pushA.id == remoteRoutineID)
        #expect(pushA.exercises?.first?.exercise?.seedID == "Barbell_Bench_Press_-_Medium_Grip")
    }

    @Test("dedupe with nothing to fold is a no-op")
    func dedupeIsNoOpWhenClean() throws {
        let (store, context) = try seededStore()
        let before = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(store.dedupeSeededRows() == 0)
        #expect(try context.fetch(FetchDescriptor<ExerciseModel>()).count == before)
        #expect(store.routines().count == 3)
        #expect(store.equipmentProfiles().count == 2)
    }

    @Test("a workout that named a folded routine is re-pointed at the survivor")
    func foldedRoutineRepointsWorkouts() throws {
        let (store, context) = try seededStore()
        let original = try #require(store.routines().first { $0.name == "Legs" })
        let workout = WorkoutModel(title: "Legs", endedAt: Date(), routineID: original.id)
        context.insert(workout)
        let remote = RoutineModel(
            name: "Legs", updatedAt: Date().addingTimeInterval(60),
            importedFromID: RoutineSeeder.starterIDs["Legs"]
        )
        context.insert(remote)
        try context.save()

        store.dedupeSeededRows()
        #expect(store.fetchRoutineModel(id: original.id) == nil)
        #expect(workout.routineID == remote.id)
    }

    @Test("the seed version lives in the store: a stale store is refreshed even after another store seeded")
    func seedVersionIsPerStore() throws {
        let (_, freshContext) = try seededStore()
        #expect(SeedState.row(in: freshContext).exerciseSeedVersion == 3)

        let staleContainer = try ModelContainer.dagym(inMemory: true)
        let staleContext = ModelContext(staleContainer)
        ExerciseSeeder.seedIfNeeded(context: staleContext)
        let bench = try #require(
            try staleContext.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        bench.instructions = "stale placeholder instructions"
        SeedState.row(in: staleContext).exerciseSeedVersion = 0
        try staleContext.save()

        ExerciseSeeder.seedIfNeeded(context: staleContext)
        #expect(bench.instructions != "stale placeholder instructions")
        #expect(SeedState.row(in: staleContext).exerciseSeedVersion == 3)
        #expect(try staleContext.fetch(FetchDescriptor<ExerciseModel>()).count == 1466)
    }

    @Test("starter routines are seeded once per store, not whenever the list is empty")
    func starterRoutinesSeedOncePerStore() throws {
        let (store, _) = try seededStore()
        for routine in store.routines() { store.deleteRoutine(id: routine.id) }
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        #expect(store.routines().isEmpty)
    }

    @Test("two merged seed-state rows collapse to the strongest one")
    func seedStateRowsCollapse() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        context.insert(SeedStateModel(exerciseSeedVersion: 2, routinesSeeded: true, equipmentSeeded: false))
        context.insert(SeedStateModel(exerciseSeedVersion: 3, routinesSeeded: false, equipmentSeeded: true))
        try context.save()

        let row = SeedState.row(in: context)
        #expect(row.exerciseSeedVersion == 3)
        #expect(row.routinesSeeded)
        #expect(row.equipmentSeeded)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SeedStateModel>()) == 1)
    }

    @Test("identical equipment profiles fold into one, keeping active")
    func duplicateProfilesFold() throws {
        let (store, context) = try seededStore()
        let profiles = try context.fetch(FetchDescriptor<EquipmentProfileModel>())
        let gym = try #require(profiles.first { $0.name == "Gym" })
        context.insert(
            EquipmentProfileModel(
                name: gym.name, isActive: true, barKg: gym.barKg, availableEquipment: gym.availableEquipment,
                plateStockKg: gym.plateStockKg, plateCounts: gym.plateCounts, collarsKg: gym.collarsKg,
                createdAt: gym.createdAt.addingTimeInterval(60)
            )
        )
        try context.save()

        #expect(store.dedupeEquipmentProfiles() == 1)
        let remaining = store.equipmentProfiles()
        #expect(remaining.count == 2)
        #expect(remaining.filter(\.isActive).count == 1)
        #expect(remaining.first { $0.name == "Gym" }?.id == gym.id)
    }

    @Test("the newest of two schedule rows wins and the older is removed")
    func duplicateScheduleRowsFold() throws {
        let (store, context) = try seededStore()
        let routine = try #require(store.routines().first)
        var newest = WeeklySchedule()
        newest.days[.monday] = routine.id
        store.saveSchedule(newest)
        context.insert(ScheduleModel(scheduleJSON: "{}", updatedAt: Date().addingTimeInterval(-3600)))
        try context.save()

        #expect(store.schedule().days[.monday] == routine.id)
        #expect(store.dedupeScheduleRows() == 1)
        #expect(try context.fetchCount(FetchDescriptor<ScheduleModel>()) == 1)
        #expect(store.schedule().days[.monday] == routine.id)
    }
}
