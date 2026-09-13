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

    @Test("a Strong-style export with a per-row lb weight converts that row to kg")
    func strongImporterConvertsPerRowLbWeight() throws {
        let header = [
            "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight", "Weight Unit",
            "Reps", "Distance", "Seconds", "Notes", "Workout Notes", "RPE"
        ]
        let row = [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "1", "185", "lbs", "8", "", "", "", ""
        ]
        let csv = ([header] + [row]).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        let result = try #require(WorkoutImport.parse(csv: csv))
        #expect(result.problems.isEmpty)
        let workout = try #require(result.workouts.first)
        let weightKg = try #require(workout.exercises.first?.sets.first?.weightKg)
        #expect(abs(weightKg - 83.91) < 0.01)
    }

    @Test("a FitNotes-style export mixing per-row lb and kg weights converts each row correctly")
    func fitNotesImporterConvertsMixedPerRowWeights() throws {
        let header = ["Date", "Exercise", "Category", "Weight", "Weight Unit", "Reps", "Distance Unit"]
        let rows = [
            ["2024-03-11", "Bench Press", "Chest", "100", "lbs", "5", ""],
            ["2024-03-11", "Bench Press", "Chest", "50", "kg", "5", ""]
        ]
        let csv = ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        let result = try #require(WorkoutImport.parse(csv: csv))
        #expect(result.problems.isEmpty)
        let sets = try #require(result.workouts.first?.exercises.first?.sets)
        #expect(abs(sets[0].weightKg - 45.36) < 0.01)
        #expect(sets[1].weightKg == 50)
    }

    @Test("comma decimals parse; ambiguous thousands-grouped values don't")
    func commaDecimalParsing() {
        #expect(ImportParsing.double("82,5") == 82.5)
        #expect(ImportParsing.double("1,000.5") == nil)
        #expect(ImportParsing.double("82.5") == 82.5)
    }

    @Test("RPE hygiene: blank/zero/negative unrated, over-scale capped, junk unrated")
    func rpeHygiene() {
        #expect(ImportParsing.rpe("") == nil)
        #expect(ImportParsing.rpe("0") == nil)
        #expect(ImportParsing.rpe("12") == 10)
        #expect(ImportParsing.rpe("7.5") == 7.5)
        #expect(ImportParsing.rpe("hard") == nil)
    }

    @Test("a leading UTF-8 BOM is stripped before header detection")
    func bomIsStripped() {
        let csv = "\u{FEFF}Date,Exercise\n2024-03-11,Squat\n"
        let rows = CSVParser.parse(csv)
        #expect(rows.first == ["Date", "Exercise"])
    }

    @Test("Hevy start_time parses an ISO fallback format")
    func hevyISOFallbackDate() {
        #expect(ImportDateFormat.hevy("2026-08-01 10:00:00") != nil)
    }

    @Test("FitNotes date parses a slash-separated fallback format")
    func fitNotesSlashFallbackDate() {
        #expect(ImportDateFormat.fitNotes("2024/03/11") != nil)
    }

    @Test("Strong never guesses a day-first numeric date")
    func strongDayFirstDateIsUnparsed() {
        #expect(ImportDateFormat.strong("11/03/2024") == nil)
    }
}
