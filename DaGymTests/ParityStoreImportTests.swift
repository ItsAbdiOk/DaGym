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
}
