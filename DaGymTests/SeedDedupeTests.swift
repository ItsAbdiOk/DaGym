import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
// Serialized: every test here seeds ~1,466 exercises into a fresh in-memory store. Run in
// parallel with itself under a loaded machine, the host has been SIGTERMed by the test runner's
// watchdog ("test crashed with signal term") — the only failure mode this suite has ever shown.
@Suite("Seed state and dedupe", .serialized)
struct SeedDedupeTests {
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
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
        let survivorIDs = Set(try context.fetch(FetchDescriptor<ExerciseModel>()).map(\.id))
        let remoteRoutineID = try simulateRemoteImport(into: context)
        #expect(try context.fetch(FetchDescriptor<ExerciseModel>()).count == survivorIDs.count * 2)

        let folded = store.dedupeSeededRows()
        #expect(folded == survivorIDs.count + 1)

        // The losers are tombstoned, not deleted (see `ExerciseSeeder.dedupe`), so the *live*
        // library is what collapses back to one row per seedID.
        let exercises = try context.fetch(FetchDescriptor<ExerciseModel>()).filter { !$0.isMergedAway }
        #expect(exercises.count == survivorIDs.count)
        #expect(Set(exercises.compactMap(\.seedID)).count == exercises.count)
        #expect(Set(exercises.map(\.id)) == survivorIDs)

        let routines = try context.fetch(FetchDescriptor<RoutineModel>()).filter { !$0.isMergedAway }
        #expect(routines.count == RoutineSeeder.starterIDs.count)
        #expect(routines.filter { $0.name == "Push A" }.count == 1)
        for slot in routines.flatMap({ $0.exercises ?? [] }) {
            let exerciseID = try #require(slot.exercise?.id)
            #expect(survivorIDs.contains(exerciseID))
        }
        // The remote routine was the newer *row* — a fresh seed — so the original, the copy the
        // user has had and may have edited, survived. The remote copy is a tombstone whose slot
        // now points at the original bench.
        let pushA = try #require(routines.first { $0.name == "Push A" })
        #expect(pushA.id != remoteRoutineID)
        let remote = try #require(
            try context.fetch(FetchDescriptor<RoutineModel>()).first { $0.id == remoteRoutineID }
        )
        #expect(remote.mergedIntoID == pushA.id)
        #expect(remote.exercises?.first?.exercise?.seedID == "Barbell_Bench_Press_-_Medium_Grip")
    }

    /// `ExerciseNoteModel.exerciseID` is a bare id, not a SwiftData relationship (CloudKit-legal,
    /// like the PR cache) — so it isn't covered by SwiftData deleting `duplicate`'s relationships
    /// and needs its own re-point in `ExerciseSeeder.fold`. Before that fix, a note left on
    /// whichever copy lost the fold vanished the moment the loser was deleted.
    @Test("a note on a folded exercise's losing copy survives, re-pointed at the survivor")
    func foldedExerciseRepointsNotes() throws {
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
        let bench = try #require(
            store.exercises().first { $0.seedID == "Barbell_Bench_Press_-_Medium_Grip" }
        )
        let duplicate = ExerciseModel(
            seedID: bench.seedID, name: bench.name, primaryMuscles: bench.primary.map(\.rawValue),
            equipment: bench.equipment, loggingStyle: bench.loggingStyle.rawKey,
            createdAt: Date().addingTimeInterval(60)
        )
        context.insert(duplicate)
        let note = ExerciseNoteModel(exerciseID: duplicate.id, text: "Elbows tucked", scope: "always")
        context.insert(note)
        try context.save()

        let folded = store.dedupeSeededRows()
        #expect(folded > 0)
        #expect(store.fetchExerciseModel(id: duplicate.id) == nil)
        #expect(note.exerciseID == bench.id)
        #expect(store.exerciseNotes(exerciseID: bench.id).contains { $0.text == "Elbows tucked" })
    }

    @Test("dedupe with nothing to fold is a no-op")
    func dedupeIsNoOpWhenClean() throws {
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
        let before = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(store.dedupeSeededRows() == 0)
        #expect(try context.fetch(FetchDescriptor<ExerciseModel>()).count == before)
        #expect(store.routines().count == RoutineSeeder.starterIDs.count)
        #expect(store.equipmentProfiles().count == 2)
    }

    @Test("a workout that named a folded routine is re-pointed at the survivor")
    func foldedRoutineRepointsWorkouts() throws {
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
        let original = try #require(store.routines().first { $0.name == "Legs" })
        // The other device's copy is older, so it wins the fold; the workout logged here
        // against the local copy follows it.
        let remote = RoutineModel(
            name: "Legs", createdAt: Date().addingTimeInterval(-600),
            importedFromID: RoutineSeeder.starterIDs["Legs"]
        )
        context.insert(remote)
        let workout = WorkoutModel(title: "Legs", endedAt: Date(), routineID: original.id)
        context.insert(workout)
        try context.save()

        store.dedupeSeededRows()
        #expect(store.fetchRoutineModel(id: original.id) == nil)
        #expect(workout.routineID == remote.id)
    }

    @Test("the seed version lives in the store: a stale store is refreshed even after another store seeded")
    func seedVersionIsPerStore() throws {
        let (_, freshContext) = try makeStoreAndContext(seed: .firstLaunch)
        #expect(SeedState.row(in: freshContext).exerciseSeedVersion == 6)

        let staleContext = try makeContext()
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
        #expect(SeedState.row(in: staleContext).exerciseSeedVersion == 6)
        #expect(try staleContext.fetch(FetchDescriptor<ExerciseModel>()).count == 1466)
    }

    @Test("starter routines are seeded once per store, not whenever the list is empty")
    func starterRoutinesSeedOncePerStore() throws {
        let (store, _) = try makeStoreAndContext(seed: .firstLaunch)
        for routine in store.routines() { store.deleteRoutine(id: routine.id) }
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        #expect(store.routines().isEmpty)
    }

    @Test("two merged seed-state rows collapse to the strongest one")
    func seedStateRowsCollapse() throws {
        let context = try makeContext()
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
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
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
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
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

/// The fold's tombstone contract (finding 1), the multi-routine schedule re-point (finding 2),
/// the `SeedState` tiebreak, and the CloudKit-legality of the mirrored schema.
@MainActor
@Suite("Seed fold tombstones and schema legality", .serialized)
struct SeedTombstoneTests {
    /// Finding 1: CloudKit imports a record *before* its children. This delivers the other
    /// device's `ExerciseModel` copy on its own, lets the fold run, and only then delivers the
    /// workout entry / PR rows that name it — the ordering `simulateRemoteImport` (one atomic
    /// graph) can never produce, and the ordering that used to lose the lot. The loser is kept
    /// as a tombstone so the late arrivals still resolve, and the next pass re-points them.
    @Test("rows that arrive after the fold are re-pointed, not orphaned")
    func lateArrivingChildrenAreRepointed() throws {
        let (_, context) = try makeStoreAndContext(seed: .firstLaunch)
        let bench = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        let remote = ExerciseModel(
            seedID: bench.seedID, name: bench.name, primaryMuscles: bench.primaryMuscles,
            equipment: bench.equipment, loggingStyle: bench.loggingStyle,
            createdAt: bench.createdAt.addingTimeInterval(60)
        )
        context.insert(remote)
        try context.save()

        // The fold runs while only the parent has synced.
        #expect(ExerciseSeeder.dedupe(in: context) > 0)
        try context.save()
        #expect(remote.mergedIntoID == bench.id)

        // Now the other device's children land.
        let workout = WorkoutModel(title: "Push A", endedAt: Date())
        context.insert(workout)
        let entry = WorkoutExerciseModel(order: 0, exercise: remote, workout: workout)
        context.insert(entry)
        let record = PersonalRecordModel(exerciseID: remote.id, kind: "e1rm", value: 120)
        context.insert(record)
        let event = PersonalRecordEventModel(exerciseID: remote.id, kind: "e1rm", value: 120)
        context.insert(event)
        let note = ExerciseNoteModel(exerciseID: remote.id, text: "Pause on chest", scope: "always")
        context.insert(note)
        try context.save()
        // The loser still exists, so nothing arrived parentless.
        #expect(entry.exercise != nil)

        #expect(ExerciseSeeder.dedupe(in: context) > 0)
        try context.save()
        #expect(entry.exercise?.id == bench.id)
        #expect(record.exerciseID == bench.id)
        #expect(event.exerciseID == bench.id)
        #expect(note.exerciseID == bench.id)
        // Settled: a further pass has nothing left to do.
        #expect(ExerciseSeeder.dedupe(in: context) == 0)
    }

    /// A tombstone is never handed out as a library exercise.
    @Test("a folded-away exercise is hidden from every read")
    func tombstonesAreHiddenFromReads() throws {
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
        let liveCount = store.exercises().count
        let bench = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        let remote = ExerciseModel(
            seedID: bench.seedID, name: bench.name, primaryMuscles: bench.primaryMuscles,
            equipment: bench.equipment, loggingStyle: bench.loggingStyle,
            createdAt: bench.createdAt.addingTimeInterval(60)
        )
        context.insert(remote)
        try context.save()
        store.dedupeSeededRows()

        #expect(store.exercises().count == liveCount)
        #expect(store.fetchExerciseModel(id: remote.id) == nil)
        #expect(store.exerciseID(seedID: "Barbell_Bench_Press_-_Medium_Grip") == bench.id)
    }

    /// Finding 6: the loser may hold the edits. Only fields the survivor still has at their
    /// seeded value are taken over, so a real edit on the survivor is never clobbered.
    @Test("rest time, increment and bar edited on the losing copy survive the fold")
    func foldCarriesExerciseEdits() throws {
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
        let bench = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        let remote = ExerciseModel(
            seedID: bench.seedID, name: bench.name, primaryMuscles: bench.primaryMuscles,
            equipment: bench.equipment, loggingStyle: bench.loggingStyle, barType: "ezBar",
            incrementKg: bench.incrementKg + 1.5, restSeconds: bench.restSeconds + 45,
            createdAt: bench.createdAt.addingTimeInterval(60)
        )
        context.insert(remote)
        try context.save()

        store.dedupeSeededRows()
        #expect(bench.restSeconds == remote.restSeconds)
        #expect(bench.incrementKg == remote.incrementKg)
        #expect(bench.barType == "ezBar")
    }

    /// Finding 6: `persistProgression` writes `stallJSON`/`trainingMaxKg` without bumping
    /// `updatedAt`, so the device that actually trained can lose the fold to one that only
    /// renamed the routine. The engine's memory is merged across rather than dropped.
    @Test("the losing routine's progression state is merged into the survivor")
    func foldMergesProgressionState() throws {
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
        let legs = try #require(store.routines().first { $0.name == "Legs" })
        let trained = try #require(store.fetchRoutineModel(id: legs.id))
        let trainedSlot = try #require(trained.exercises?.first)
        trainedSlot.stallJSON = #"{"missStreak":2}"#
        trainedSlot.trainingMaxKg = 142.5
        let exercise = try #require(trainedSlot.exercise)

        // An older row that only carries a rename — and its own untouched slot for the same
        // lift. Oldest wins the fold, so it is the survivor and the trained copy the loser.
        let renamed = RoutineModel(
            name: "Leg Day", createdAt: Date().addingTimeInterval(-600),
            importedFromID: RoutineSeeder.starterIDs["Legs"]
        )
        context.insert(renamed)
        let renamedSlot = RoutineExerciseModel(order: 0, exercise: exercise, routine: renamed)
        context.insert(renamedSlot)
        try context.save()

        store.dedupeSeededRows()
        #expect(store.fetchRoutineModel(id: trained.id) == nil)
        #expect(renamedSlot.stallJSON == #"{"missStreak":2}"#)
        #expect(renamedSlot.trainingMaxKg == 142.5)
    }

    /// Finding 2: the re-point used to go through the single-routine `days` view, which only
    /// ever sees — and only ever writes — a day's first routine.
    @Test("a folded routine on a two-routine day keeps the day's other routine")
    func foldedRoutineKeepsMultiRoutineDay() throws {
        let (store, context) = try makeStoreAndContext(seed: .firstLaunch)
        let legs = try #require(store.routines().first { $0.name == "Legs" })
        let arms = try #require(store.routines().first { $0.name == "Pull B" })
        var schedule = WeeklySchedule()
        schedule.setRoutines([legs.id, arms.id], on: .monday)
        store.saveSchedule(schedule)

        let remote = RoutineModel(
            name: "Legs", createdAt: Date().addingTimeInterval(-600),
            importedFromID: RoutineSeeder.starterIDs["Legs"]
        )
        context.insert(remote)
        try context.save()

        store.dedupeSeededRows()
        #expect(store.schedule().dayRoutines[.monday] == [remote.id, arms.id])
    }

    /// The `WeeklySchedule.days` setter itself: writing a day's first routine must not throw
    /// away the rest of that day's list.
    @Test("setting a day's first routine keeps the routines planned behind it")
    func daysSetterKeepsTrailingRoutines() {
        let first = UUID()
        let second = UUID()
        let replacement = UUID()
        var schedule = WeeklySchedule()
        schedule.setRoutines([first, second], on: .monday)
        schedule.days[.monday] = replacement
        #expect(schedule.dayRoutines[.monday] == [replacement, second])
        schedule.days[.monday] = nil
        #expect(schedule.dayRoutines[.monday] == nil)
    }

    /// Finding 6: `updatedAt` alone is not a total order. Two rows stamped in the same instant
    /// let each device keep a different one and delete the other's, which bounced
    /// `routinesSeeded` back to false and re-seeded all 13 starters into a deliberately
    /// emptied store.
    @Test("seed-state rows with identical timestamps pick the same survivor on every device")
    func seedStateTiebreakIsDeterministic() throws {
        let stamp = Date()
        let ids = [UUID(), UUID(), UUID()]
        var survivors: [UUID] = []
        for ordering in [ids, Array(ids.reversed())] {
            let context = try makeContext()
            for id in ordering {
                context.insert(SeedStateModel(id: id, routinesSeeded: true, updatedAt: stamp))
            }
            try context.save()
            survivors.append(SeedState.row(in: context).id)
        }
        #expect(survivors[0] == survivors[1])
        #expect(survivors[0] == ids.min { $0.uuidString < $1.uuidString })
    }

    /// CloudKit's two hard rules for a mirrored schema: every relationship must be optional and
    /// no attribute may be unique. Breaking either stops the container loading at all — on a
    /// user's device, not here — so the schema is asserted rather than reviewed.
    @Test("the mirrored schema stays CloudKit-legal: optional relationships, no unique attributes")
    func mirroredSchemaIsCloudKitLegal() {
        let schema = Schema(DaGymSchema.mainModels)
        for entity in schema.entities {
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) is not optional")
            }
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
            }
        }
    }
}
