import Foundation
import Testing
@testable import GymCore

/// Behaviour pinned by the optimisation pass: cached date formatters, Strong's letter set codes,
/// end-before-start timestamps, the RPE floor, unit-word column headers and the CSV size cap.
@Suite("Import: review fixes")
struct ImportFixesTests {
    private static func csv(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map { row in
            row.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    private static let strongHeader = [
        "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight (kg)", "Reps",
        "Distance", "Seconds", "Notes", "Workout Notes", "RPE"
    ]

    private static let hevyHeader = [
        "title", "start_time", "end_time", "description", "exercise_title", "superset_id",
        "exercise_notes", "set_index", "set_type", "weight_kg", "reps", "distance_km",
        "duration_seconds", "rpe"
    ]

    // MARK: - Dates

    @Test("the shared formatters parse the same text to the same instant on every call")
    func cachedFormattersAreStable() {
        let first = ImportDateFormat.strong("2024-03-11 18:24:00")
        let second = ImportDateFormat.strong("2024-03-11 18:24:00")
        #expect(first != nil && first == second)
        #expect(ImportDateFormat.hevy("11 Mar 2024, 18:24") == ImportDateFormat.hevy("11 Mar 2024, 18:24"))
        #expect(ImportDateFormat.fitNotes("2024-03-11") == ImportDateFormat.fitNotes("2024-03-11"))
    }

    @Test("the last-string memo returns the right date when the text changes, and memoises a miss")
    func memoFollowsChanges() {
        let march = ImportDateFormat.strong("2024-03-11 18:24:00")
        let april = ImportDateFormat.strong("2024-04-11 18:24:00")
        #expect(march != april)
        #expect(ImportDateFormat.strong("2024-03-11 18:24:00") == march)
        #expect(ImportDateFormat.strong("garbage") == nil)
        #expect(ImportDateFormat.strong("garbage") == nil)
        #expect(ImportDateFormat.strong("2024-04-11 18:24:00") == april)
    }

    @Test("the fallback list still catches an ISO start_time in a Hevy column")
    func fallbackStillWorks() {
        #expect(ImportDateFormat.hevy("2024-03-11T18:24:00Z") != nil)
        #expect(ImportDateFormat.fitNotes("2024/03/11") != nil)
    }

    @Test("the memo is safe to hit from many threads at once")
    func memoIsThreadSafe() async {
        let texts = (0..<50).map { "2024-03-\(String(format: "%02d", $0 % 28 + 1)) 10:00:00" }
        await withTaskGroup(of: Bool.self) { group in
            for text in texts {
                group.addTask { ImportDateFormat.strong(text) != nil }
            }
            for await parsed in group { #expect(parsed) }
        }
    }

    // MARK: - Strong Set Order

    @Test("a bare D/F (or D1/F2) Set Order is a drop/failure set; digits and W stay as before")
    func strongLetterSetCodes() throws {
        let csv = Self.csv(Self.strongHeader, [
            ["2024-03-11 18:24:00", "Push", "1h", "Bench Press", "W1", "40", "10", "", "", "", "", ""],
            ["2024-03-11 18:24:00", "Push", "1h", "Bench Press", "1", "60", "8", "", "", "", "", ""],
            ["2024-03-11 18:24:00", "Push", "1h", "Bench Press", "D", "50", "8", "", "", "", "", ""],
            ["2024-03-11 18:24:00", "Push", "1h", "Bench Press", "D2", "40", "8", "", "", "", "", ""],
            ["2024-03-11 18:24:00", "Push", "1h", "Bench Press", "F", "60", "3", "", "", "", "", ""],
            ["2024-03-11 18:24:00", "Push", "1h", "Bench Press", "Dropset", "45", "8", "", "", "", "", ""],
            ["2024-03-11 18:24:00", "Push", "1h", "Bench Press", "Failure", "60", "2", "", "", "", "", ""]
        ])
        let result = try #require(WorkoutImport.parse(csv: csv))
        let kinds = try #require(result.workouts.first?.exercises.first?.sets.map(\.kind))
        #expect(kinds == [.warmup, .working, .drop, .drop, .failure, .drop, .failure])
    }

    @Test("2025 exports: a bare Weight header, 'Rest Timer' rows and a '10m' duration")
    func strongRestTimerRowsAreNotSets() throws {
        // Verbatim shape of a real September-2026 export: `Weight` carries no unit, every set is
        // followed by a `Rest Timer` row with the rest length in `Seconds`, and the whole file
        // writes `0`/`0.0` rather than blanks.
        let header = [
            "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight", "Reps",
            "Distance", "Seconds", "Notes", "Workout Notes", "RPE"
        ]
        let stamp = "2025-08-12 20:30:20"
        func set(_ order: String, _ weight: String, _ reps: String, _ seconds: String) -> [String] {
            [stamp, "Monday", "5m", "Cable Crossover", order, weight, reps, "0", seconds, "", "", ""]
        }
        let csv = Self.csv(header, [
            set("1", "7.0", "10.0", "0.0"),
            set("Rest Timer", "0", "0.0", "120.0"),
            set("2", "7.0", "10.0", "0.0"),
            set("Rest Timer", "0", "0.0", "120.0")
        ])
        let result = try #require(WorkoutImport.parse(csv: csv, assumedWeightUnit: .kg))
        let workout = try #require(result.workouts.first)
        let sets = try #require(workout.exercises.first?.sets)
        #expect(sets.count == 2)
        #expect(sets.allSatisfy { $0.durationSeconds == nil && $0.weightKg == 7 && $0.reps == 10 })
        #expect(result.weightUnitAssumed)
        #expect(workout.endedAt == workout.startedAt.addingTimeInterval(5 * 60))
        #expect(result.problems.isEmpty)
    }

    // MARK: - Hevy end_time

    @Test("an end_time before start_time is dropped rather than stored as a negative duration")
    func endBeforeStartIsDropped() throws {
        let csv = Self.csv(Self.hevyHeader, [
            ["Push", "11 Mar 2024, 18:24", "11 Mar 2024, 17:24", "", "Bench Press", "", "", "0", "normal",
             "60", "8", "", "", ""]
        ])
        let result = try #require(WorkoutImport.parse(csv: csv))
        let workout = try #require(result.workouts.first)
        #expect(workout.endedAt == nil)
        #expect(result.problems.isEmpty)
    }

    @Test("an end_time equal to or after start_time is kept")
    func endAfterStartIsKept() throws {
        let csv = Self.csv(Self.hevyHeader, [
            ["Push", "11 Mar 2024, 18:24", "11 Mar 2024, 19:30", "", "Bench Press", "", "", "0", "normal",
             "60", "8", "", "", ""]
        ])
        let workout = try #require(WorkoutImport.parse(csv: csv)?.workouts.first)
        let ended = try #require(workout.endedAt)
        #expect(ended.timeIntervalSince(workout.startedAt) == 66 * 60)
    }

    // MARK: - RPE floor

    @Test("an RPE below the app's 5…10 scale imports as unrated, not as RPE 5")
    func lowRPEIsUnrated() {
        #expect(ImportParsing.rpe("4") == nil)
        #expect(ImportParsing.rpe("4.5") == nil)
        #expect(ImportParsing.rpe("5") == 5)
        #expect(ImportParsing.rpe("7.5") == 7.5)
        #expect(ImportParsing.rpe("42") == 10)
        #expect(ImportParsing.rpe("0") == nil)
    }

    // MARK: - Column unit

    @Test("a header names a unit only as a whole word; one naming both resolves to neither")
    func columnUnitIsWordBounded() {
        #expect(ImportRow.columnUnit(named: "weight (kg)") == .kg)
        #expect(ImportRow.columnUnit(named: "weight (lbs)") == .lb)
        #expect(ImportRow.columnUnit(named: "weight_kg") == .kg)
        #expect(ImportRow.columnUnit(named: "weight_lbs") == .lb)
        #expect(ImportRow.columnUnit(named: "weight") == nil)
        #expect(ImportRow.columnUnit(named: "weight (kg/lb)") == nil)
        #expect(ImportRow.columnUnit(named: "weight_lbs_or_kg") == nil)
        #expect(ImportRow.columnUnit(named: "bodyweight (kgs)") == .kg)
    }

    // MARK: - Size cap

    @Test("a file over the byte cap is reported as one problem instead of being parsed")
    func oversizedFileIsAProblem() throws {
        let header = Self.strongHeader.joined(separator: ",") + "\n"
        let row = "2024-03-11 18:24:00,Push,1h,Bench Press,1,60,8,,,,,\n"
        let repeats = CSVParser.maxBytes / row.utf8.count + 1
        let csv = header + String(repeating: row, count: repeats)
        #expect(CSVParser.isOversized(csv))
        #expect(CSVParser.parse(csv).isEmpty)
        let result = try #require(WorkoutImport.parse(csv: csv))
        #expect(result.source == .strong)
        #expect(result.workouts.isEmpty)
        #expect(result.problems.count == 1)
        #expect(result.problems.first?.message.contains("too large") == true)
    }

    @Test("an oversized file with an unknown header is still nil, like any unrecognised file")
    func oversizedUnknownHeaderIsNil() {
        let csv = "a,b,c\n" + String(repeating: "1,2,3\n", count: CSVParser.maxBytes / 6 + 1)
        #expect(WorkoutImport.parse(csv: csv) == nil)
    }
}
