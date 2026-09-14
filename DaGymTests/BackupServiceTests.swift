import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("BackupService")
struct BackupServiceTests {
    /// Builds a small but representative store: a custom exercise, a
    /// routine using it, a finished workout, a body measurement and an
    /// equipment profile.
    private func seededStore() throws -> (store: WorkoutStore, context: ModelContext) {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

        let bench = store.createCustomExercise(
            name: "Zercher Squat", primary: [.quads], equipment: "barbell", style: .weightReps
        )
        store.toggleFavorite(id: bench.id)

        let draft = RoutineExerciseDraft(
            exerciseID: bench.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        store.saveRoutine(id: nil, name: "Legs", exercises: [draft])

        let session = store.startWorkout(routineID: nil)
        session.exercises = [store.autoFilledEntry(for: bench)]
        session.exercises[0].sets[0].isDone = true
        session.exercises[0].sets[0].weightKg = 60
        session.exercises[0].sets[0].reps = 8
        store.sync(session: session)

        context.insert(BodyMeasurementModel(bodyweightKg: 82))
        try context.save()

        EquipmentSeeder.seedIfNeeded(store: store)
        return (store, context)
    }

    @Test("export then import into a fresh container reproduces counts")
    func exportImportRoundTrip() throws {
        let (sourceStore, sourceContext) = try seededStore()
        let document = BackupService.export(context: sourceContext)

        #expect(document.exercises.contains { $0.name == "Zercher Squat" && $0.isFavorite })
        #expect(document.routines.contains { $0.name == "Legs" })
        #expect(document.workouts.count == 1)
        #expect(document.bodyMeasurements.count == 1)
        #expect(document.equipmentProfiles.count == 2)
        _ = sourceStore

        let destinationContainer = try ModelContainer.dagym(inMemory: true)
        let destinationContext = ModelContext(destinationContainer)
        let report = BackupService.import(document: document, context: destinationContext)

        #expect(report.exercisesImported == 1)
        #expect(report.routinesImported == 1)
        #expect(report.workoutsImported == 1)
        #expect(report.bodyMeasurementsImported == 1)
        #expect(report.equipmentProfilesImported == 2)
        #expect(report.problems.isEmpty)

        let destinationStore = WorkoutStore(context: destinationContext)
        #expect(destinationStore.routines().count == 1)
        #expect(destinationStore.equipmentProfiles().count == 2)
    }

    @Test("re-importing the same file twice produces no duplicates")
    func reimportIsIdempotent() throws {
        let (_, sourceContext) = try seededStore()
        let document = BackupService.export(context: sourceContext)

        let destinationContainer = try ModelContainer.dagym(inMemory: true)
        let destinationContext = ModelContext(destinationContainer)

        let firstReport = BackupService.import(document: document, context: destinationContext)
        #expect(firstReport.workoutsImported == 1)

        let secondReport = BackupService.import(document: document, context: destinationContext)
        #expect(secondReport.workoutsImported == 0)
        #expect(secondReport.workoutsSkipped == 1)
        #expect(secondReport.exercisesImported == 0)
        #expect(secondReport.routinesImported == 0)
        #expect(secondReport.equipmentProfilesImported == 0)

        let destinationStore = WorkoutStore(context: destinationContext)
        let workoutCount = try destinationContext.fetchCount(FetchDescriptor<WorkoutModel>())
        #expect(workoutCount == 1)
        #expect(destinationStore.routines().count == 1)
    }

    @Test("preview predicts the same counts import produces, without mutating the store")
    func previewMatchesImport() throws {
        let (_, sourceContext) = try seededStore()
        let document = BackupService.export(context: sourceContext)

        let destinationContainer = try ModelContainer.dagym(inMemory: true)
        let destinationContext = ModelContext(destinationContainer)

        let preview = BackupService.preview(document: document, context: destinationContext)
        let workoutCountBeforeImport = try destinationContext.fetchCount(FetchDescriptor<WorkoutModel>())
        #expect(workoutCountBeforeImport == 0)

        let report = BackupService.import(document: document, context: destinationContext)
        #expect(preview.workoutsImported == report.workoutsImported)
        #expect(preview.routinesImported == report.routinesImported)
        #expect(preview.exercisesImported == report.exercisesImported)
    }

    @Test("importing a routine referencing a missing exercise skips that slot and reports it")
    func missingExerciseReported() throws {
        let plannedSet = BackupPlannedSet(order: 0, kind: "working", targetReps: 8)
        let routineExercise = BackupRoutineExercise(
            order: 0, exerciseSeedID: nil, exerciseName: "Nonexistent Exercise", plannedSets: [plannedSet]
        )
        let routine = BackupRoutine(id: UUID(), name: "Ghost Day", exercises: [routineExercise])
        let document = BackupDocument(
            exportedAt: Date(), appVersion: "1.0", routines: [routine], preferences: BackupPreferences()
        )

        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let report = BackupService.import(document: document, context: context)

        #expect(report.routinesImported == 1)
        #expect(report.problems.count == 1)

        let store = WorkoutStore(context: context)
        let loaded = try #require(store.routines().first { $0.name == "Ghost Day" })
        #expect(loaded.exercises.isEmpty)
    }

    // MARK: - Seed tombstones

    /// A second iCloud device's first launch: a second copy of one seeded exercise and of one
    /// starter routine, both of which `dedupeSeededRows()` folds into a **tombstone** rather than
    /// deleting. Returns the id of the routine copy.
    @discardableResult
    private func plantRemoteDuplicates(
        _ store: WorkoutStore, context: ModelContext
    ) throws -> UUID {
        let seedID = "Barbell_Bench_Press_-_Medium_Grip"
        let original = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first { $0.seedID == seedID }
        )
        let copy = ExerciseModel(
            seedID: seedID, name: original.name, primaryMuscles: original.primaryMuscles,
            equipment: original.equipment, loggingStyle: original.loggingStyle,
            createdAt: original.createdAt.addingTimeInterval(60)
        )
        // Favouriting it is what puts a *seeded* row into the export at all (see
        // `exportExercises`), which is how a tombstone could reach the file.
        copy.isFavorite = true
        context.insert(copy)

        let routineCopy = RoutineModel(
            name: "Push A", createdAt: Date().addingTimeInterval(60),
            updatedAt: Date().addingTimeInterval(60),
            importedFromID: RoutineSeeder.starterIDs["Push A"]
        )
        context.insert(routineCopy)
        context.insert(RoutineExerciseModel(order: 0, exercise: copy, routine: routineCopy))
        try context.save()
        return routineCopy.id
    }

    /// Deleting a duplicate is a permanent CloudKit history loss, so the deduper tombstones it
    /// instead (`mergedIntoID`). Every read path hides a tombstone — but export fetched
    /// `ExerciseModel`/`RoutineModel` unfiltered, so the duplicate went into the backup, and the
    /// importer, which has no idea it was ever a tombstone, put it back on the other device as a
    /// second real row. A routine tombstone still owns its slots, so that one arrived complete.
    @Test("a tombstoned duplicate never reaches the export")
    func tombstonesAreNotExported() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        try plantRemoteDuplicates(store, context: context)
        store.dedupeSeededRows()

        let tombstoned = try context.fetch(FetchDescriptor<RoutineModel>()).filter(\.isMergedAway)
        #expect(!tombstoned.isEmpty, "the duplicate must be a tombstone, not a deletion")

        let document = BackupService.export(context: context)
        #expect(document.routines.filter { $0.name == "Push A" }.count == 1)
        #expect(document.routines.count == store.routines().count)
        let benchRows = document.exercises.filter { $0.seedID == "Barbell_Bench_Press_-_Medium_Grip" }
        #expect(benchRows.count == 1)
        let exportedIDs = Set(document.routines.map(\.id))
        #expect(exportedIDs.isDisjoint(with: Set(tombstoned.map(\.id))))
    }

    /// The files already written before the export filter existed still contain both halves of a
    /// fold. Importing one must not leave the lifter with two "Push A"s and a second bench press
    /// hiding in their library: the duplicates fold again on the receiving device.
    @Test("an older file that already contains a duplicate still converges on import")
    func olderFileWithDuplicateConverges() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        try plantRemoteDuplicates(store, context: context)
        // Exported *before* the fold: exactly the shape of a file written by an older build.
        let olderFile = BackupService.export(context: context)
        #expect(olderFile.routines.filter { $0.name == "Push A" }.count == 2)

        let freshContainer = try ModelContainer.dagym(inMemory: true)
        let freshContext = ModelContext(freshContainer)
        ExerciseSeeder.seedIfNeeded(context: freshContext)
        let freshStore = WorkoutStore(context: freshContext)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: freshStore)
        BackupService.import(document: olderFile, context: freshContext)
        freshStore.dedupeSeededRows()

        #expect(freshStore.routines().filter { $0.name == "Push A" }.count == 1)
        let live = try freshContext.fetch(FetchDescriptor<ExerciseModel>()).filter { !$0.isMergedAway }
        #expect(live.filter { $0.seedID == "Barbell_Bench_Press_-_Medium_Grip" }.count == 1)
        // And the survivor is a row the app can actually see — not a tombstone the index
        // resolved every imported slot onto.
        let bench = try #require(
            freshStore.exercises().first { $0.name.contains("Barbell Bench Press") }
        )
        #expect(freshStore.fetchExerciseModel(id: bench.id)?.isMergedAway == false)
    }

    // MARK: - Child linking

    /// The 20-site SwiftData trap: assigning a parent's children array while the inverse
    /// (`routine:` / `workout:` / `routineExercise:`) has already linked them makes SwiftData
    /// rebuild a relationship it is mid-way through updating. What must hold afterwards is that
    /// every child is reachable *through the parent array* — the inverse alone populated it.
    @Test("imported routines, workouts and their sets are reachable through their parents")
    func importedChildrenAreLinkedThroughTheInverse() throws {
        let (_, sourceContext) = try seededStore()
        let document = BackupService.export(context: sourceContext)

        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        BackupService.import(document: document, context: context)

        let routine = try #require(
            try context.fetch(FetchDescriptor<RoutineModel>()).first { $0.name == "Legs" }
        )
        let slot = try #require(routine.exercises?.first)
        #expect(routine.exercises?.count == 1)
        #expect(slot.plannedSets?.count == 1)
        #expect(slot.routine?.id == routine.id)

        let workout = try #require(try context.fetch(FetchDescriptor<WorkoutModel>()).first)
        let entry = try #require(workout.exercises?.first)
        #expect(entry.workout?.id == workout.id)
        #expect(entry.sets?.isEmpty == false)
    }

    /// The same for the `.gymplan` path, which had three of the remaining sites.
    @Test("a shared plan's slots and planned sets are reachable through their parents")
    func sharedPlanChildrenAreLinkedThroughTheInverse() throws {
        let (store, sourceContext) = try seededStore()
        let routineID = try #require(store.routines().first { $0.name == "Legs" }?.id)
        let plan = try #require(PlanShareService.exportRoutine(id: routineID, context: sourceContext))

        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let report = PlanShareService.importPlan(document: plan, context: context)
        #expect(report.routinesImported == 1)

        let routine = try #require(try context.fetch(FetchDescriptor<RoutineModel>()).first)
        #expect(routine.exercises?.count == 1)
        let slot = try #require(routine.exercises?.first)
        #expect(slot.plannedSets?.count == 1)
        #expect(slot.routine?.id == routine.id)
    }

    @Test("corrupted JSON surfaces a typed decoding error")
    func corruptedJSONSurfacesError() {
        let garbage = Data("{not valid json".utf8)
        #expect(throws: BackupCodec.CodecError.self) {
            try BackupCodec.decode(garbage)
        }
    }
}
