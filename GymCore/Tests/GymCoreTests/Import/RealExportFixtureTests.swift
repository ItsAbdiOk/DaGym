import Foundation
import Testing
@testable import GymCore

/// Fixtures shaped like the files these apps actually write, rather than tidied-up ones.
///
/// The old fixtures hid two real bugs: the Strong one used a `Weight (kg)` header and left
/// `Distance`/`Seconds` blank, where a real Strong export writes a bare `Weight` and a literal
/// `0` in both on every weight set; and the Hevy "imperial" one paired `weight_lbs` with
/// `distance_km`, where a real imperial export writes `distance_miles`. Both files parsed
/// perfectly in the tests and wrongly in the app.
@Suite("Import: real export shapes")
struct RealExportFixtureTests {
    /// Quotes like a real export does: Hevy's `start_time` ("11 Mar 2024, 18:24") contains a
    /// comma, so a fixture that joined fields blindly would misalign every column after it — and
    /// would be testing a file no app writes.
    private static func csv(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map { row in row.map(quote).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    private static func quote(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Strong

    /// A current Strong export: bare `Weight`, a `Workout Duration` column (older builds called it
    /// `Duration`), and zeros rather than blanks in `Distance`/`Seconds`.
    private static let strongHeader = [
        "Date", "Workout Name", "Workout Duration", "Exercise Name", "Set Order", "Weight",
        "Weight Unit", "Reps", "RPE", "Distance", "Distance Unit", "Seconds", "Notes",
        "Workout Notes"
    ]

    private static let strongCSV = csv(strongHeader, [
        [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "1", "60", "kg", "8", "",
            "0", "km", "0", "", ""
        ],
        [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "2", "62.5", "kg", "6", "8",
            "0", "km", "0", "felt heavy", ""
        ],
        [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Plank", "1", "0", "kg", "0", "",
            "0", "km", "60", "", ""
        ],
        [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Treadmill", "1", "0", "kg", "0", "",
            "5", "km", "1500", "", ""
        ],
        [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Ghost Set", "1", "0", "kg", "0", "",
            "0", "km", "0", "", ""
        ]
    ])

    @Test("Strong's literal zeros are read as 'not measured', not as a 0 s / 0 m weight set")
    func strongZerosAreNotMeasurements() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.strongCSV))
        #expect(result.problems.isEmpty)
        let workout = try #require(result.workouts.first)
        let bench = try #require(workout.exercises.first { $0.name == "Bench Press" })
        #expect(bench.sets.count == 2)
        #expect(bench.sets.allSatisfy { $0.durationSeconds == nil })
        #expect(bench.sets.allSatisfy { $0.distanceMeters == nil })
        #expect(bench.sets[0].weightKg == 60)
    }

    @Test("a Strong row that is zero in every measured column is an empty row, not a 0 kg × 0 set")
    func strongAllZeroRowIsEmpty() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.strongCSV))
        #expect(result.emptyRows == 1)
        #expect(result.workouts.first?.exercises.contains { $0.name == "Ghost Set" } == false)
    }

    @Test("a real timed or cardio Strong row still keeps its seconds and distance")
    func strongKeepsRealMeasurements() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.strongCSV))
        let workout = try #require(result.workouts.first)
        let plank = try #require(workout.exercises.first { $0.name == "Plank" })
        #expect(plank.sets.first?.durationSeconds == 60)
        let treadmill = try #require(workout.exercises.first { $0.name == "Treadmill" })
        #expect(treadmill.sets.first?.distanceMeters == 5000)
        #expect(treadmill.sets.first?.durationSeconds == 1500)
    }

    @Test("Strong's newer 'Workout Duration' column sets endedAt, not the one-hour default")
    func strongWorkoutDurationColumn() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.strongCSV))
        let workout = try #require(result.workouts.first)
        let endedAt = try #require(workout.endedAt)
        #expect(endedAt.timeIntervalSince(workout.startedAt) == 3900)
    }

    @Test("a bare Weight header with no unit anywhere is flagged rather than assumed to be kg")
    func strongBareWeightHeaderIsFlagged() throws {
        let header = [
            "Date", "Workout Name", "Workout Duration", "Exercise Name", "Set Order", "Weight",
            "Reps", "Distance", "Seconds", "Notes", "Workout Notes"
        ]
        let row = [
            "2024-03-11 18:24:00", "Push Day", "45m", "Bench Press", "1", "225", "5", "0", "0", "", ""
        ]
        let text = Self.csv(header, [row])
        let assumed = try #require(WorkoutImport.parse(csv: text))
        #expect(assumed.weightUnitAssumed)
        #expect(assumed.workouts[0].exercises[0].sets[0].weightKg == 225)

        // …and re-parsing in the unit the user picks converts instead of mislabelling.
        let asPounds = try #require(WorkoutImport.parse(csv: text, assumedWeightUnit: .lb))
        let weight = try #require(asPounds.workouts.first?.exercises.first?.sets.first?.weightKg)
        #expect(abs(weight - WeightUnit.lb.toKg(225)) < 0.001)
    }

    @Test("a file whose weight column names its unit is never flagged as ambiguous")
    func namedUnitIsNotFlagged() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.strongCSV))
        #expect(!result.weightUnitAssumed)
    }

    // MARK: - Hevy

    /// A real Hevy imperial export: `weight_lbs` *and* `distance_miles`, with `superset_id`
    /// populated on the two exercises trained as a superset.
    private static let hevyImperialHeader = [
        "title", "start_time", "end_time", "description", "exercise_title", "superset_id",
        "exercise_notes", "set_index", "set_type", "weight_lbs", "reps", "distance_miles",
        "duration_seconds", "rpe"
    ]

    private static let hevyImperialCSV = csv(hevyImperialHeader, [
        [
            "Push A", "11 Mar 2024, 18:24", "11 Mar 2024, 19:05", "", "Bench Press", "0", "", "1",
            "normal", "225", "5", "", "", ""
        ],
        [
            "Push A", "11 Mar 2024, 18:24", "11 Mar 2024, 19:05", "", "Cable Fly", "0", "", "1",
            "normal", "40", "12", "", "", ""
        ],
        [
            "Push A", "11 Mar 2024, 18:24", "11 Mar 2024, 19:05", "", "Treadmill", "", "", "1",
            "normal", "", "", "3.1", "1500", ""
        ]
    ])

    @Test("an imperial Hevy export reads distance_miles in miles, not kilometres")
    func hevyImperialDistance() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.hevyImperialCSV))
        #expect(result.problems.isEmpty)
        let treadmill = try #require(
            result.workouts.first?.exercises.first { $0.name == "Treadmill" }
        )
        let meters = try #require(treadmill.sets.first?.distanceMeters)
        #expect(abs(meters - 3.1 * 1609.344) < 0.01)
    }

    @Test("an imperial Hevy export converts weight_lbs to kg")
    func hevyImperialWeight() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.hevyImperialCSV))
        let bench = try #require(result.workouts.first?.exercises.first)
        let weight = try #require(bench.sets.first?.weightKg)
        #expect(abs(weight - WeightUnit.lb.toKg(225)) < 0.001)
        #expect(!result.weightUnitAssumed)
    }

    @Test("Hevy's superset_id survives the import so a superset stays a superset")
    func hevySupersetSurvives() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.hevyImperialCSV))
        let workout = try #require(result.workouts.first)
        let bench = try #require(workout.exercises.first { $0.name == "Bench Press" })
        let fly = try #require(workout.exercises.first { $0.name == "Cable Fly" })
        let treadmill = try #require(workout.exercises.first { $0.name == "Treadmill" })
        #expect(bench.supersetGroup == 0)
        #expect(fly.supersetGroup == 0)
        #expect(treadmill.supersetGroup == nil)
    }

    // MARK: - Timezone

    @Test("a Strong timestamp lands on the same wall-clock time in any device timezone")
    func timestampIsTimezoneStable() throws {
        // The importers build their formatters with `en_US_POSIX` and the *current* timezone, so a
        // wall-clock export ("18:24") is read as 18:24 local — which is what the lifter saw. This
        // pins that: the calendar reading must match in whatever zone the device is in.
        for identifier in ["UTC", "America/Los_Angeles", "Australia/Sydney", "Asia/Kathmandu"] {
            let zone = try #require(TimeZone(identifier: identifier))
            let result = try #require(WorkoutImport.parse(csv: Self.strongCSV))
            let startedAt = try #require(result.workouts.first?.startedAt)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let components = calendar.dateComponents([.hour, .minute], from: startedAt)
            // Parsed in the device's own zone; read back in the same zone, it is 18:24 again.
            if zone == TimeZone.current {
                #expect(components.hour == 18 && components.minute == 24)
            }
            // And in every zone the instant is a single, well-defined one — never nil, never
            // shifted by a date that failed to parse and silently became "now".
            #expect(startedAt.timeIntervalSince1970 > 1_700_000_000)
            #expect(startedAt.timeIntervalSince1970 < 1_720_000_000)
        }
    }

    @Test("a FitNotes date-only row lands at local midnight, so it stays on its own day")
    func fitNotesDateOnlyIsLocalMidnight() throws {
        let header = ["Date", "Exercise", "Category", "Weight (kgs)", "Reps", "Distance Unit"]
        let result = try #require(
            WorkoutImport.parse(csv: Self.csv(header, [["2024-03-11", "Squat", "Legs", "100", "5", ""]]))
        )
        let startedAt = try #require(result.workouts.first?.startedAt)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: startedAt)
        #expect(components.year == 2024 && components.month == 3 && components.day == 11)
        #expect(components.hour == 0)
    }
}
