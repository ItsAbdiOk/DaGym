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

    @Test("corrupted JSON surfaces a typed decoding error")
    func corruptedJSONSurfacesError() {
        let garbage = Data("{not valid json".utf8)
        #expect(throws: BackupCodec.CodecError.self) {
            try BackupCodec.decode(garbage)
        }
    }
}
