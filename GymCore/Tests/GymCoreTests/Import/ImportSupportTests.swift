import Foundation
import Testing
@testable import GymCore

@Suite("ColumnMap")
struct ImportSupportTests {
    @Test("an exact match wins outright over a longer header that also contains the words")
    func exactMatchWinsOverLongerHeader() {
        let columns = ColumnMap(header: ["Date", "Weight Unit", "Weight", "Reps"])
        #expect(columns.columnName(containing: ["weight"]) == "weight")
    }

    @Test("with no exact match, the pick is deterministic across repeated calls")
    func noExactMatchIsDeterministic() {
        let columns = ColumnMap(header: ["Date", "Bodyweight (kg)", "Weight (kg)", "Reps"])
        let first = columns.columnName(containing: ["weight"])
        let second = columns.columnName(containing: ["weight"])
        #expect(first == second)
        #expect(first == "bodyweight (kg)")
    }

    @Test("a Strong-style export with both a weight and a weight-unit column picks the exact column")
    func strongImporterPicksExactWeightColumn() throws {
        let header = [
            "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight", "Weight Unit",
            "Reps", "Distance", "Seconds", "Notes", "Workout Notes", "RPE"
        ]
        let row = [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "1", "60", "kg", "8", "", "", "", ""
        ]
        let csv = ([header] + [row]).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        let result = try #require(WorkoutImport.parse(csv: csv))
        #expect(result.problems.isEmpty)
        let workout = try #require(result.workouts.first)
        let exercise = try #require(workout.exercises.first)
        #expect(exercise.sets.first?.weightKg == 60)
    }
}
