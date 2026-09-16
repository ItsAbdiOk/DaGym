import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The `DaGym/Data` re-review fixes: the routine fold keeps the user's copy (F1), the routine
/// tombstone sweep never cascades through live children (F4), an encoded-empty schedule row is
/// blank (F2), the plan-target comparison reads the engine's set (F3), the launch auto-finish
/// reaches the finish hooks (F5), and the fixed-step load grids follow the lifter's unit.
@MainActor
@Suite("Data re-review fixes")
struct DataRereviewFixTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Edits the seeded "Upper A" the way a lifter does: a working target on the first lift and
    /// the second lift swapped for "Dumbbell Flyes". Returns the routine id.
    private func editUpperA(_ store: WorkoutStore) throws -> UUID {
        let upperA = try #require(store.routines().first { $0.name == "Upper A" })
        var drafts = try #require(store.routineDrafts(id: upperA.id)).drafts
        let workingIndex = try #require(drafts[0].sets.firstIndex { $0.kind == .working })
        drafts[0].sets[workingIndex].targetWeightKg = 82.5
        let flye = try #require(store.exercises(matching: "Dumbbell Flyes").first)
        drafts[1].exerciseID = flye.id
        store.saveRoutine(id: upperA.id, name: "Upper A", exercises: drafts)
        return upperA.id
    }

    /// The swapped-in lift is checked by name: a wipe re-seeds the library under new ids.
    private func upperAIsTheEditedCopy(_ store: WorkoutStore, routineID: UUID) throws {
        let live = store.routines().filter { $0.name == "Upper A" }
        #expect(live.count == 1)
        #expect(live.first?.id == routineID)
        let drafts = try #require(store.routineDrafts(id: routineID)).drafts
        #expect(drafts[0].sets.contains { $0.targetWeightKg == 82.5 })
        let flye = try #require(store.exercises(matching: "Dumbbell Flyes").first)
        #expect(drafts[1].exerciseID == flye.id)
    }

    // MARK: - F1: the edited copy survives a fresh seed

    /// Seed, edit a starter, seed again (a second iCloud device's first launch delivers exactly
    /// this: pristine copies with `updatedAt = now`), fold. "Newest wins" handed the fold to the
    /// pristine copy, and the lifter's planned weight and swapped lift went with the tombstone.
    @Test("a starter routine edited between two seeds keeps the edits after the fold")
    func editedStarterSurvivesReseed() throws {
        let (store, _) = try makeStoreAndContext(seed: .stocked)
        let edited = try editUpperA(store)

        // `seedStarters` skips a starter the store has, so plant the pristine copy the way a
        // second device's launch delivers it: same starter id, fresh timestamps.
        let pristine = RoutineModel(
            name: "Upper A", createdAt: Date().addingTimeInterval(60),
            updatedAt: Date().addingTimeInterval(60), importedFromID: RoutineSeeder.starterIDs["Upper A"]
        )
        store.context.insert(pristine)
        store.save()
        #expect(store.routines().filter { $0.name == "Upper A" }.count == 2)

        store.dedupeSeededRows()
        try upperAIsTheEditedCopy(store, routineID: edited)
    }

    /// The restore path: wipe, import the backup, launch (which folds). The wipe used to re-seed
    /// pristine starters and the restored routine lost the fold to one; now it re-seeds no
    /// routines at all, so the fold has nothing to weigh and the backup's copy is the only one.
    @Test("a backup's edited starter routine comes back intact after a wipe-then-restore")
    func restoredStarterSurvivesWipeThenRestore() throws {
        let (store, context) = try makeStoreAndContext(seed: .stocked)
        let edited = try editUpperA(store)
        let document = BackupService.export(context: context)

        let preferences = Preferences(suite: makeSuite("data.rereview.wipe"))
        store.wipeAllData(preferences: preferences, effects: .inert)
        #expect(store.routines().isEmpty, "the wipe re-seeds no routines")
        BackupService.import(document: document, context: context)
        store.dedupeSeededRows()

        try upperAIsTheEditedCopy(store, routineID: edited)
    }

    /// The inverse of the two cases above: the *older* copy is the pristine one. Phone A seeded
    /// Upper A in January and never opened it; the lifter rebuilt it on new phone B in March,
    /// then signed into iCloud. "Oldest wins" handed the fold to A's untouched seed.
    @Test("a routine rebuilt on a newer device beats an older device's never-opened seed")
    func editedNewerCopyBeatsPristineOlderSeed() throws {
        let (store, context) = try makeStoreAndContext(seed: .stocked)
        let edited = try editUpperA(store)
        let day: TimeInterval = 24 * 60 * 60
        let local = try #require(store.fetchRoutineModel(id: edited))
        local.createdAt = Date().addingTimeInterval(-10 * day)
        local.updatedAt = Date().addingTimeInterval(-5 * day)
        let bench = try #require(store.exercises(matching: "Barbell Bench Press - Medium Grip").first)
        let remote = RoutineModel(
            name: "Upper A", createdAt: Date().addingTimeInterval(-60 * day),
            updatedAt: Date().addingTimeInterval(-60 * day + 0.2),
            importedFromID: RoutineSeeder.starterIDs["Upper A"]
        )
        context.insert(remote)
        let slot = RoutineExerciseModel(
            order: 0, exercise: store.fetchExerciseModel(id: bench.id), routine: remote
        )
        context.insert(slot)
        try context.save()

        store.dedupeSeededRows()
        try upperAIsTheEditedCopy(store, routineID: edited)
    }

    /// The survivor is the older *row*, which must never mean keeping the older *judgement*: a
    /// loser trained more recently carries its stall state across even when the survivor has one.
    @Test("a more recently trained loser's stall state replaces the survivor's")
    func newerLoserStallStateWins() throws {
        let (store, context) = try makeStoreAndContext(seed: .stocked)
        let legs = try #require(store.routines().first { $0.name == "Legs" })
        let survivor = try #require(store.fetchRoutineModel(id: legs.id))
        let survivorSlot = try #require(survivor.exercises?.first)
        survivorSlot.stallJSON = #"{"missStreak":1}"#
        survivor.updatedAt = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let exercise = try #require(survivorSlot.exercise)

        let loser = RoutineModel(
            name: "Legs", createdAt: Date(), updatedAt: Date(),
            importedFromID: RoutineSeeder.starterIDs["Legs"]
        )
        context.insert(loser)
        let loserSlot = RoutineExerciseModel(
            order: 0, stallJSON: #"{"missStreak":2}"#, exercise: exercise, routine: loser
        )
        context.insert(loserSlot)
        try context.save()

        store.dedupeSeededRows()
        #expect(store.fetchRoutineModel(id: loser.id) == nil)
        #expect(survivorSlot.stallJSON == #"{"missStreak":2}"#)
    }

    // MARK: - F4: the sweep never cascades through live children

    /// Device B kept training and editing its copy of "Legs" while offline for longer than the
    /// grace period, then reconnected: its slots and its workout name the tombstone. The sweep
    /// used to delete the tombstone outright, and `.cascade` took B's slots with it.
    @Test("a tombstone edited by an offline device hands its slots and workouts to the survivor")
    func sweptTombstoneHandsChildrenToSurvivor() throws {
        let (store, context) = try makeStoreAndContext(seed: .stocked)
        let legs = try #require(store.routines().first { $0.name == "Legs" })
        let local = try #require(store.fetchRoutineModel(id: legs.id))
        let squat = try #require(local.exercises?.first { $0.exercise?.name == "Barbell Squat" }?.exercise)
        let localSlotIDs = Set((local.exercises ?? []).map(\.id))
        // The other device's copy is older, so it wins; it only has squat.
        let remote = RoutineModel(
            name: "Legs", createdAt: Date().addingTimeInterval(-600),
            importedFromID: RoutineSeeder.starterIDs["Legs"]
        )
        context.insert(remote)
        context.insert(RoutineExerciseModel(order: 0, exercise: squat, routine: remote))
        try context.save()
        store.dedupeSeededRows()
        #expect(local.mergedIntoID == remote.id)

        // Long past the grace period, and edited (and trained) on the offline device since.
        local.mergedAt = Date().addingTimeInterval(-ExerciseSeeder.tombstoneGracePeriod - 86_400)
        local.updatedAt = Date()
        let workout = WorkoutModel(title: "Legs", endedAt: Date(), routineID: local.id)
        context.insert(workout)
        try context.save()

        store.dedupeSeededRows()
        let remoteSlots = try #require(remote.exercises)
        #expect(remoteSlots.count == 4, "squat kept once; the three other lifts moved across")
        #expect(remoteSlots.filter { $0.exercise?.id == squat.id }.count == 1)
        #expect(Set(remoteSlots.map(\.id)).intersection(localSlotIDs).count == 3)
        #expect(workout.routineID == remote.id)
        // The tombstone survives the pass that re-pointed its workout, and goes on the next.
        store.dedupeSeededRows()
        #expect(!(try context.fetch(FetchDescriptor<RoutineModel>()).contains { $0.id == local.id }))
        #expect(try context.fetchCount(FetchDescriptor<RoutineExerciseModel>()) > 0)
    }

    /// The ordinary case — nothing touched the tombstone after the fold — still reclaims it,
    /// with its redundant slots dropped one by one, not through the cascade.
    @Test("an untouched tombstone is reclaimed after the grace period without moving anything")
    func untouchedTombstoneIsReclaimed() throws {
        let (store, context) = try makeStoreAndContext(seed: .stocked)
        let legs = try #require(store.routines().first { $0.name == "Legs" })
        let local = try #require(store.fetchRoutineModel(id: legs.id))
        let remote = RoutineModel(
            name: "Legs", createdAt: Date().addingTimeInterval(-600),
            importedFromID: RoutineSeeder.starterIDs["Legs"]
        )
        context.insert(remote)
        try context.save()
        store.dedupeSeededRows()
        // Folded a month and a day ago, last edited before that.
        let mergedAt = Date().addingTimeInterval(-ExerciseSeeder.tombstoneGracePeriod - 86_400)
        local.mergedAt = mergedAt
        local.updatedAt = mergedAt.addingTimeInterval(-86_400)
        try context.save()

        store.dedupeSeededRows()
        #expect(!(try context.fetch(FetchDescriptor<RoutineModel>()).contains { $0.id == local.id }))
        #expect((remote.exercises ?? []).isEmpty)
    }

    // MARK: - F2: an emptied schedule is blank

    @Test("a schedule the user cleared again does not swallow the backup's schedule")
    func encodedEmptyScheduleIsBlank() throws {
        let encoded = try #require(String(data: JSONEncoder().encode(WeeklySchedule()), encoding: .utf8))
        #expect(BackupService.isBlank(ScheduleModel(scheduleJSON: encoded)))

        let sourceContext = try makeContext()
        sourceContext.insert(ScheduleModel(scheduleJSON: #"{"mon":["push"]}"#))
        try sourceContext.save()
        let document = BackupService.export(context: sourceContext)

        let destinationContext = try makeContext()
        destinationContext.insert(ScheduleModel(scheduleJSON: encoded))
        try destinationContext.save()
        BackupService.import(document: document, context: destinationContext)
        let restored = try #require(try destinationContext.fetch(FetchDescriptor<ScheduleModel>()).first)
        #expect(restored.scheduleJSON == #"{"mon":["push"]}"#)
    }

    // MARK: - F3: the plan target is the first working set's, nil included

    /// A top-set-only plan: working set 1 open, working set 2 at 80 kg. The engine records the
    /// first working set's target (nil); the app used to read the first *targeted* set (80), so
    /// the two never matched and any routine save put the plan back in front of the engine.
    @Test("a rename never re-applies a top-set-only plan over the engine's prescription")
    func topSetOnlyPlanSurvivesRename() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id,
            sets: [
                PlannedSetDraft(kind: .working, targetReps: 8),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)
            ]
        )
        let routine = store.saveRoutine(
            id: nil, name: "Push", rule: .linear(incrementKg: 2.5), exercises: [draft]
        )
        let session = store.startWorkout(routineID: routine.id)
        for index in 0..<2 {
            session.exercises[0].sets[index].weightKg = 80
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)

        store.saveRoutine(
            id: routine.id, name: "Push Day", rule: .linear(incrementKg: 2.5), exercises: [draft]
        )
        let next = store.startWorkout(routineID: routine.id)
        let entry = try #require(next.exercises.first)
        #expect(entry.whyTitle != "From your updated plan")
        #expect(entry.sets[1].weightKg == 82.5)
        store.discard(session: next)
    }

    // MARK: - F5: the launch auto-finish reaches the finish hooks

    /// `DaGymApp.seed()` now binds Health and the notification scheduler *before* the purge.
    /// The App struct itself is not unit-testable, so this pins the half that is: a workout the
    /// purge auto-finishes goes through both hooks exactly like a tapped Finish.
    @Test("purge's auto-finish fires the finish hooks")
    func purgeAutoFinishFiresHooks() throws {
        let (store, _) = try makeStoreAndContext(seed: .stocked)
        let legs = try #require(store.routines().first { $0.name == "Legs" })
        let session = store.startWorkout(routineID: legs.id)
        session.exercises[0].sets[0].isDone = true
        store.sync(session: session)
        let workoutID = try #require(session.workoutID)
        store.workout(id: workoutID)?.startedAt = Date().addingTimeInterval(-48 * 60 * 60)
        store.save()

        var finished: [UUID] = []
        var observed: [UUID] = []
        store.onWorkoutFinished = { finished.append($0.id) }
        store.workoutFinishedObservers.append { observed.append($0.id) }
        store.purgeUnfinished(olderThan: Date().addingTimeInterval(-24 * 60 * 60))

        #expect(finished == [workoutID])
        #expect(observed == [workoutID])
    }

    // MARK: - Load grids follow the lifter's unit

    @Test("dumbbell, kettlebell and machine steps are 5/10/10 lb for an lb lifter")
    func fixedStepGridsFollowUnit() throws {
        let store = try makeStore()
        let equipment = store.activeEquipment()
        let dumbbell = store.createCustomExercise(
            name: "DB Press", primary: [.chest], equipment: "Dumbbell", style: .weightReps
        )
        let kettlebell = store.createCustomExercise(
            name: "KB Swing", primary: [.glutes], equipment: "Kettlebell", style: .weightReps
        )
        var machine = store.createCustomExercise(
            name: "Leg Press", primary: [.quads], equipment: "Machine", style: .weightReps
        )
        machine.incrementKg = 0

        let fiveLb = WeightUnit.lb.toKg(5)
        let tenLb = WeightUnit.lb.toKg(10)
        #expect(store.loadGrid(for: dumbbell, equipment: equipment, unit: .kg) == .step(2))
        #expect(store.loadGrid(for: dumbbell, equipment: equipment, unit: .lb) == .step(fiveLb))
        #expect(store.loadGrid(for: kettlebell, equipment: equipment, unit: .lb) == .step(tenLb))
        #expect(store.loadGrid(for: machine, equipment: equipment, unit: .lb) == .step(tenLb))
    }
}

/// The routine fold's survivor rule on its own: edited beats pristine, then two pristine copies
/// fold to the oldest and two edited ones to the latest edit.
@MainActor
@Suite("Routine fold survivor rule")
struct RoutineFoldSurvivorTests {
    private let day: TimeInterval = 24 * 60 * 60

    @Test("edited beats pristine; pristine pairs go oldest-first, edited pairs latest-edit-first")
    func survivorOrder() {
        let pristineOld = RoutineModel(
            createdAt: Date().addingTimeInterval(-2 * day), updatedAt: Date().addingTimeInterval(-2 * day)
        )
        let pristineNew = RoutineModel(
            createdAt: Date().addingTimeInterval(-day), updatedAt: Date().addingTimeInterval(-day)
        )
        #expect(WorkoutStore.routineSurvivesFirst(pristineOld, pristineNew))
        #expect(!WorkoutStore.routineSurvivesFirst(pristineNew, pristineOld))
        let editedOld = RoutineModel(
            createdAt: Date().addingTimeInterval(-9 * day), updatedAt: Date().addingTimeInterval(-8 * day)
        )
        let editedNew = RoutineModel(
            createdAt: Date().addingTimeInterval(-3 * day), updatedAt: Date().addingTimeInterval(-day)
        )
        #expect(WorkoutStore.routineSurvivesFirst(editedNew, editedOld))
        #expect(WorkoutStore.routineSurvivesFirst(editedNew, pristineOld))
        #expect(!WorkoutStore.routineSurvivesFirst(pristineOld, editedNew))
        // A fresh seed's `updatedAt` lands milliseconds after its `createdAt`: not an edit.
        #expect(!WorkoutStore.routineWasEdited(RoutineModel()))
    }
}
