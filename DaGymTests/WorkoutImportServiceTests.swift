import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutImportService")
struct WorkoutImportServiceTests {
    private static let header = [
        "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight (kg)", "Reps",
        "Distance", "Seconds", "Notes", "Workout Notes", "RPE"
    ]

    nonisolated private static func row(_ fields: [String]) -> String { fields.joined(separator: ",") }

    private static let csv = ([header] + [
        ["2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "1", "60", "8", "", "", "", "", ""],
        ["2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "2", "65", "6", "", "", "", "", ""]
    ]).map(row).joined(separator: "\n") + "\n"

    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        return WorkoutStore(context: context)
    }

    @Test("preview parses the fixture and flags the unmatched exercise")
    func previewParses() throws {
        let store = try makeStore()
        let preview = try #require(WorkoutImportService.preview(csv: Self.csv, store: store))
        #expect(preview.source == .strong)
        #expect(preview.workouts.count == 1)
        #expect(preview.setsCount == 2)
        #expect(preview.unmatchedExerciseNames == ["Bench Press"])
        #expect(preview.problems.isEmpty)
    }

    @Test("apply creates a backfilled workout, a custom exercise and caches a PR")
    func applyImportsAndCachesPR() throws {
        let store = try makeStore()
        let preview = try #require(WorkoutImportService.preview(csv: Self.csv, store: store))
        let report = WorkoutImportService.apply(preview: preview, store: store)

        #expect(report.workoutsImported == 1)
        #expect(report.setsImported == 2)
        #expect(report.exercisesCreated == 1)
        #expect(report.problems.isEmpty)

        let history = store.history()
        #expect(history.count == 1)
        let record = try #require(history.first)
        let detail = store.workoutDetail(id: record.id)
        #expect(detail.isBackfilled)

        let created = store.exercises(matching: "Bench Press")
        #expect(created.count == 1)
        #expect(created.first?.isCustom == true)

        let records = store.personalRecords()
        let benchRecords = try #require(records.first { $0.exerciseName == "Bench Press" })
        #expect(benchRecords.records.contains { $0.kindLabel == "Estimated 1RM" })
    }

    @Test("re-applying the same file imports nothing new")
    func reapplyIsANoOp() throws {
        let store = try makeStore()
        let firstPreview = try #require(WorkoutImportService.preview(csv: Self.csv, store: store))
        _ = WorkoutImportService.apply(preview: firstPreview, store: store)

        let secondPreview = try #require(WorkoutImportService.preview(csv: Self.csv, store: store))
        let secondReport = WorkoutImportService.apply(preview: secondPreview, store: store)

        #expect(secondReport.workoutsImported == 0)
        #expect(secondReport.workoutsSkipped == 1)
        // The exercise already exists (created by the first apply), so no new custom exercise.
        #expect(secondReport.exercisesCreated == 0)
        #expect(store.history().count == 1)
    }
}
