import Foundation
import Testing
@testable import GymCore

/// Parsing a third-party export is the app's only untrusted-input boundary, and the file comes
/// from someone else's app, someone else's device, or a spreadsheet the user edited by hand.
/// Everything here is a value that used to either **trap** (`Int(Double.infinity)`,
/// `9223372036854775807 * 3600`) or land in the store and break something later (a non-finite
/// weight makes `JSONEncoder` throw, so one bad row made every future backup fail permanently).
///
/// The contract these lock in: parsing never crashes, a bad cell becomes a reported problem, and
/// nothing out of range is ever stored.
@Suite("Import: hostile input")
struct ImportHostileInputTests {
    private static func csv(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static let strongHeader = [
        "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight (kg)", "Reps",
        "Distance", "Seconds", "Notes", "Workout Notes", "RPE"
    ]

    private static func strongRow(
        reps: String = "5", weight: String = "60", distance: String = "0",
        seconds: String = "0", duration: String = "1h 5m"
    ) -> [String] {
        [
            "2024-03-11 18:24:00", "Push Day", duration, "Bench Press", "1", weight, reps,
            distance, seconds, "", "", ""
        ]
    }

    // MARK: - The values that used to trap

    @Test(
        "a reps cell that is inf, nan or beyond Int becomes a problem instead of trapping",
        arguments: ["1e999", "-1e999", "inf", "-inf", "nan", "NaN", "99999999999999999999", "1e30"]
    )
    func hostileRepsNeverTraps(cell: String) throws {
        let result = try #require(
            WorkoutImport.parse(csv: Self.csv(Self.strongHeader, [Self.strongRow(reps: cell)]))
        )
        #expect(result.workouts.isEmpty)
        #expect(result.problems.count == 1)
        #expect(result.problems[0].message.contains("reps"))
    }

    @Test(
        "a weight cell that is inf, nan or negative is rejected, never stored",
        arguments: ["1e999", "inf", "nan", "-100", "-1e999", "999999"]
    )
    func hostileWeightIsRejected(cell: String) throws {
        let result = try #require(
            WorkoutImport.parse(csv: Self.csv(Self.strongHeader, [Self.strongRow(weight: cell)]))
        )
        #expect(result.workouts.isEmpty)
        #expect(result.problems.count == 1)
        #expect(result.problems[0].message.contains("weight"))
    }

    @Test("a clock duration whose components overflow Int is a problem, not a trap")
    func overflowingClockDuration() {
        #expect(ImportParsing.durationSecondsFromClock("9223372036854775807:00") == nil)
        #expect(ImportParsing.durationSecondsFromClock("1:9223372036854775807:00") == nil)
        #expect(ImportParsing.durationSecondsFromClock("99999999:00:00") == nil)
        #expect(ImportParsing.durationSecondsFromClock("1:02:03") == 3723)
    }

    @Test("a free-text duration whose components overflow Int is a problem, not a trap")
    func overflowingFreeTextDuration() {
        #expect(ImportParsing.durationSecondsFromFreeText("9223372036854775807h") == nil)
        #expect(ImportParsing.durationSecondsFromFreeText("1h 5m") == 3900)
    }

    @Test("a FitNotes Time cell that would overflow becomes a problem row")
    func fitNotesOverflowingTimeIsAProblem() throws {
        let header = ["Date", "Exercise", "Category", "Weight (kgs)", "Reps", "Distance Unit", "Time"]
        let rows = [["2024-03-11", "Plank", "Abs", "0", "0", "", "9223372036854775807:00"]]
        let result = try #require(WorkoutImport.parse(csv: Self.csv(header, rows)))
        #expect(result.workouts.isEmpty)
        #expect(result.problems.count == 1)
    }

    // MARK: - Values that parsed but should never be stored

    @Test("10^9 reps is out of range, not a new personal record")
    func absurdRepsRejected() throws {
        let result = try #require(
            WorkoutImport.parse(csv: Self.csv(Self.strongHeader, [Self.strongRow(reps: "1000000000")]))
        )
        #expect(result.workouts.isEmpty)
        #expect(result.problems.count == 1)
    }

    @Test("every stored weight is finite, so the store stays encodable")
    func everyStoredWeightIsEncodable() throws {
        let rows = [
            Self.strongRow(weight: "nan"), Self.strongRow(weight: "60"),
            Self.strongRow(weight: "1e999"), Self.strongRow(weight: "-5")
        ]
        let result = try #require(WorkoutImport.parse(csv: Self.csv(Self.strongHeader, rows)))
        let weights = result.workouts.flatMap { $0.exercises.flatMap { $0.sets.map(\.weightKg) } }
        #expect(weights == [60])
        #expect(weights.allSatisfy { $0.isFinite })
        #expect(result.problems.count == 3)
    }

    @Test("a distance beyond any plausible session is rejected rather than stored")
    func absurdDistanceRejected() throws {
        let header = ["Date", "Exercise", "Category", "Weight (kgs)", "Reps", "Distance",
                      "Distance Unit", "Time"]
        let rows = [["2024-03-11", "Running", "Cardio", "0", "0", "1e12", "km", ""]]
        let result = try #require(WorkoutImport.parse(csv: Self.csv(header, rows)))
        #expect(result.workouts.isEmpty)
        #expect(result.problems.count == 1)
    }

    @Test("a bad row never takes the rest of the file with it")
    func oneBadRowDoesNotAbortTheImport() throws {
        let rows = [
            Self.strongRow(reps: "5"), Self.strongRow(reps: "nan"), Self.strongRow(reps: "8")
        ]
        let result = try #require(WorkoutImport.parse(csv: Self.csv(Self.strongHeader, rows)))
        #expect(result.problems.count == 1)
        let sets = try #require(result.workouts.first?.exercises.first?.sets)
        #expect(sets.map(\.reps) == [5, 8])
    }

    // MARK: - Free text

    @Test("an unbounded notes cell is truncated rather than carried into the store")
    func hugeNoteIsTruncated() throws {
        let note = String(repeating: "x", count: 100_000)
        let row = [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "1", "60", "5", "0", "0",
            note, "", ""
        ]
        let result = try #require(WorkoutImport.parse(csv: Self.csv(Self.strongHeader, [row])))
        let parsed = try #require(result.workouts.first?.exercises.first?.note)
        #expect(parsed.count == ImportLimits.maxTextLength)
    }

    // MARK: - Size

    @Test("a 50 MB file parses without crashing", .timeLimit(.minutes(1)))
    func fiftyMegabyteFileParses() throws {
        // 50 MB, most of it inside quoted `Notes` cells — the shape that actually stresses the
        // parser (a single huge field, quote handling, no row-per-byte allocation) rather than
        // just making the test slow. Nothing here may trap, truncate the file, or lose a row.
        let header = ["Date", "Exercise", "Category", "Weight (kgs)", "Reps", "Distance Unit", "Notes"]
        let note = String(repeating: "a", count: 25_000)
        let row = "2024-03-11,Bench Press,Chest,60,5,,\"\(note)\"\n"
        let rowCount = (50 * 1024 * 1024) / row.utf8.count
        let text = header.joined(separator: ",") + "\n" + String(repeating: row, count: rowCount)
        #expect(text.utf8.count > 40 * 1024 * 1024)

        let result = try #require(WorkoutImport.parse(csv: text))
        #expect(result.problems.isEmpty)
        #expect(result.workouts.count == 1)
        #expect(result.workouts[0].exercises[0].sets.count == rowCount)
        // …and the note came through the quote handling intact, then bounded on the way out.
        #expect(result.workouts[0].exercises[0].note.count == ImportLimits.maxTextLength)
    }

    @Test("a file with very many rows keeps every one of them", .timeLimit(.minutes(1)))
    func manyRowsAreAllKept() throws {
        let header = ["Date", "Exercise", "Category", "Weight (kgs)", "Reps", "Distance Unit"]
        let rowCount = 100_000
        let text = header.joined(separator: ",") + "\n"
            + String(repeating: "2024-03-11,Bench Press,Chest,60,5,\n", count: rowCount)
        let result = try #require(WorkoutImport.parse(csv: text))
        #expect(result.problems.isEmpty)
        #expect(result.workouts[0].exercises[0].sets.count == rowCount)
    }
}
