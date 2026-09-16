import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Store parity: import and library search")
struct ParityStoreImportTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func library(_ names: [String]) -> ParseContext {
        ParseContext(
            unit: .kg,
            library: names.map { ParseContext.ExerciseCandidate(id: UUID(), name: $0, equipment: "barbell") }
        )
    }

    private static let strongHeader = [
        "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight (kg)", "Reps",
        "Distance", "Seconds", "Notes", "Workout Notes", "RPE"
    ]

    private static func strongCSV(_ rows: [[String]]) -> String {
        ([strongHeader] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    // MARK: - Import rec 2: never guess between close matches

    @Test("a name equally close to two library entries is unmatched")
    func nearTieIsUnmatched() {
        let incline = library(["Incline Barbell Bench Press", "Incline Dumbbell Bench Press"])
        #expect(WorkoutImportService.matchedExerciseID("Incline Bench Press", context: incline) == nil)

        let squats = library(["Barbell Squat", "Weighted Squat"])
        #expect(WorkoutImportService.matchedExerciseID("Squat", context: squats) == nil)
    }

    @Test("a clear winner still matches")
    func clearWinnerMatches() {
        let bench = library(["Barbell Bench Press"])
        let matched = WorkoutImportService.matchedExerciseID("Bench Press (Barbell)", context: bench)
        #expect(matched == bench.library.first?.id)
    }

    // MARK: - Import rec 5: muscles and style for invented exercises

    @Test("an invented exercise gets its muscles from its name")
    func inventedExerciseMusclesFromName() throws {
        let store = try makeStore()
        let csv = Self.strongCSV([
            ["2024-03-11 18:24:00", "Pull", "1h", "Kirk Shrug Machine", "1", "60", "12", "", "", "", "", ""]
        ])
        let preview = try #require(WorkoutImportService.preview(csv: csv, store: store))
        _ = WorkoutImportService.apply(preview: preview, store: store)

        let created = try #require(store.exercises(matching: "Kirk Shrug").first)
        #expect(created.primary == [.traps])
        #expect(created.loggingStyle == .weightReps)
    }

    @Test("time-and-distance-only rows make a cardio exercise with no muscles")
    func inventedCardioExercise() throws {
        let store = try makeStore()
        let csv = Self.strongCSV([
            ["2024-03-11 18:24:00", "Cardio", "1h", "Treadmill", "1", "0", "0", "5", "1500", "", "", ""]
        ])
        let preview = try #require(WorkoutImportService.preview(csv: csv, store: store))
        _ = WorkoutImportService.apply(preview: preview, store: store)

        let created = try #require(store.exercises(matching: "Treadmill").first)
        #expect(created.loggingStyle == .cardio)
        #expect(created.primary.isEmpty)
    }

    @Test("a FitNotes category names the muscle when the name says nothing")
    func inventedExerciseMusclesFromCategory() throws {
        let store = try makeStore()
        let csv = """
        Date,Exercise,Category,Weight (kgs),Reps,Distance,Distance Unit,Time
        2024-03-11,Some Invented Lift,Shoulders,20,10,,,

        """
        let preview = try #require(WorkoutImportService.preview(csv: csv, store: store))
        _ = WorkoutImportService.apply(preview: preview, store: store)

        let created = try #require(store.exercises(matching: "Some Invented Lift").first)
        #expect(created.primary == [.delts])
    }

    // MARK: - Import rec 11: library search

    @Test("every query token must hit name, muscle, equipment or style; aliases expand")
    func librarySearchTokens() throws {
        let store = try makeStore()
        store.createCustomExercise(
            name: "Dumbbell Bench Press", primary: [.chest], equipment: "dumbbell", style: .weightReps
        )
        store.createCustomExercise(
            name: "Dumbbell Pull-Over", primary: [.lats], equipment: "dumbbell", style: .weightReps
        )
        store.createCustomExercise(
            name: "Barbell Row", primary: [.lats], equipment: "barbell", style: .weightReps
        )

        #expect(store.exercises(matching: "chest dumbbell").map(\.name) == ["Dumbbell Bench Press"])
        #expect(store.exercises(matching: "db press").map(\.name) == ["Dumbbell Bench Press"])
        #expect(store.exercises(matching: "pullover").map(\.name) == ["Dumbbell Pull-Over"])
        #expect(store.exercises(matching: "PULL-OVER").map(\.name) == ["Dumbbell Pull-Over"])
        #expect(store.exercises(matching: "lats").count == 2)
        #expect(store.exercises(matching: "chest row").isEmpty)
    }

    @Test("search ignores accents")
    func librarySearchFoldsDiacritics() throws {
        let store = try makeStore()
        store.createCustomExercise(
            name: "Développé couché", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        #expect(store.exercises(matching: "developpe").map(\.name) == ["Développé couché"])
    }

    // MARK: - Dedupe, supersets and an honest preview

    /// The dedupe key used to be `startedAt|title`. Rename an imported workout and re-import the
    /// same file and it came straight back in as a second copy, because the key had moved.
    @Test("re-importing after renaming an imported workout doesn't duplicate it")
    func renamingDoesNotDefeatDedupe() throws {
        let store = try makeStore()
        let csv = Self.strongCSV([
            ["2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "1", "60", "8", "", "", "", "", ""]
        ])
        let first = try #require(WorkoutImportService.preview(csv: csv, store: store))
        #expect(WorkoutImportService.apply(preview: first, store: store).workoutsImported == 1)

        let workout = try #require(
            try store.context.fetch(FetchDescriptor<WorkoutModel>()).first
        )
        workout.title = "Push A"
        store.save()

        let second = try #require(WorkoutImportService.preview(csv: csv, store: store))
        let report = WorkoutImportService.apply(preview: second, store: store)
        #expect(report.workoutsImported == 0)
        #expect(report.workoutsSkipped == 1)
        #expect(try store.context.fetchCount(FetchDescriptor<WorkoutModel>()) == 1)
    }

    @Test("the same workout arriving twice in one batch is inserted once")
    func duplicateWithinOneBatchIsCollapsed() throws {
        let store = try makeStore()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let exercise = ImportedExercise(
            name: "Bench Press", sets: [ImportedSet(kind: .working, weightKg: 60, reps: 8)]
        )
        let workout = ImportedWorkout(
            startedAt: startedAt, title: "Push A", externalID: "hevy-1", exercises: [exercise]
        )
        let result = ImportResult(source: .hevy, workouts: [workout, workout], problems: [])
        let preview = WorkoutImportService.preview(result: result, store: store)
        let report = WorkoutImportService.apply(preview: preview, store: store)
        #expect(report.workoutsImported == 1)
        #expect(report.workoutsSkipped == 1)
    }

    /// A Hevy CSV export writes "11 Mar 2024, 18:24" — no seconds — while the Hevy API returns the
    /// real timestamp. Importing both used to give the lifter two copies of every session.
    @Test("the same session from the CSV and from the API is imported once")
    func csvAndAPIImportsDoNotDuplicate() throws {
        let store = try makeStore()
        let csv = ([
            "title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps",
            "Push A,\"11 Mar 2024, 18:24\",\"11 Mar 2024, 19:05\",Bench Press,1,normal,60,8"
        ]).joined(separator: "\n") + "\n"
        let fromCSV = try #require(WorkoutImportService.preview(csv: csv, store: store))
        #expect(WorkoutImportService.apply(preview: fromCSV, store: store).workoutsImported == 1)

        let apiStart = try #require(
            WorkoutImport.parse(csv: csv)?.workouts.first?.startedAt
        ).addingTimeInterval(37)
        let fromAPI = ImportResult(
            source: .hevy,
            workouts: [
                ImportedWorkout(
                    startedAt: apiStart, title: "Push A", externalID: "hevy-1",
                    exercises: [
                        ImportedExercise(
                            name: "Bench Press",
                            sets: [ImportedSet(kind: .working, weightKg: 60, reps: 8)]
                        )
                    ]
                )
            ],
            problems: []
        )
        let preview = WorkoutImportService.preview(result: fromAPI, store: store)
        #expect(preview.alreadyImportedCount == 1)
        let report = WorkoutImportService.apply(preview: preview, store: store)
        #expect(report.workoutsImported == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<WorkoutModel>()) == 1)
    }

    @Test("an imported superset keeps its grouping on the workout exercises")
    func supersetGroupSurvivesImport() throws {
        let store = try makeStore()
        let sets = [ImportedSet(kind: .working, weightKg: 60, reps: 8)]
        let workout = ImportedWorkout(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000), title: "Push A",
            exercises: [
                ImportedExercise(name: "Bench Press", supersetGroup: 0, sets: sets),
                ImportedExercise(name: "Cable Fly", supersetGroup: 0, sets: sets),
                ImportedExercise(name: "Triceps Pushdown", sets: sets)
            ]
        )
        let result = ImportResult(source: .hevy, workouts: [workout], problems: [])
        let preview = WorkoutImportService.preview(result: result, store: store)
        _ = WorkoutImportService.apply(preview: preview, store: store)
        let model = try #require(try store.context.fetch(FetchDescriptor<WorkoutModel>()).first)
        let groups = (model.exercises ?? []).sorted { $0.order < $1.order }.map(\.supersetGroup)
        #expect(groups == [0, 0, nil])
    }

    /// The preview used to say "12 workouts" even when all twelve were already in the store, and
    /// never said what a matched name had been matched *to*.
    @Test("the preview counts only what will actually be imported, and names every match")
    func previewIsHonestAboutWhatWillHappen() throws {
        let store = try makeStore()
        ExerciseSeeder.seedIfNeeded(context: store.context)
        let csv = Self.strongCSV([
            ["2024-03-11 18:24:00", "Push Day", "1h 5m", "Squat", "1", "100", "5", "", "", "", "", ""]
        ])
        let first = try #require(WorkoutImportService.preview(csv: csv, store: store))
        #expect(first.newWorkoutCount == 1)
        #expect(first.alreadyImportedCount == 0)
        let match = try #require(first.matchedExercises.first { $0.sourceName == "Squat" })
        #expect(match.libraryName.localizedCaseInsensitiveContains("squat"))
        _ = WorkoutImportService.apply(preview: first, store: store)

        let second = try #require(WorkoutImportService.preview(csv: csv, store: store))
        #expect(second.workouts.count == 1)
        #expect(second.alreadyImportedCount == 1)
        #expect(second.newWorkoutCount == 0)
    }

    /// "Squat (Bodyweight)" is a different lift from a barbell squat, and merging its history into
    /// the barbell's rewrites that lift's personal records.
    @Test("a known-but-absent qualifier becomes its own exercise, not the barbell seed")
    func absentQualifierDoesNotStealTheBarbellSeed() throws {
        let store = try makeStore()
        ExerciseSeeder.seedIfNeeded(context: store.context)
        let barbellID = store.exerciseID(seedID: "Barbell_Squat")
        #expect(barbellID != nil)
        let library = ImportExerciseLibrary(context: store.context)
        #expect(WorkoutImportService.seededExerciseID(for: "Squat (Bodyweight)", library: library) == nil)
        #expect(WorkoutImportService.seededExerciseID(for: "Squat", library: library) == barbellID)
    }
}
