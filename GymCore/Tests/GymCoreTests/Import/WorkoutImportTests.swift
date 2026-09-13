import Foundation
import Testing
@testable import GymCore

@Suite("WorkoutImport")
struct WorkoutImportTests {
    private static func csvRow(_ fields: [String]) -> String {
        fields.map(quote).joined(separator: ",")
    }

    private static func quote(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func csv(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map(csvRow).joined(separator: "\n") + "\n"
    }

    // MARK: - Strong

    private static let strongHeader = [
        "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight (kg)", "Reps",
        "Distance", "Seconds", "Notes", "Workout Notes", "RPE"
    ]

    private static let strongCSV = csv(Self.strongHeader, [
        ["2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "W1", "40", "10", "", "", "", "", ""],
        [
            "2024-03-11 18:24:00", "Push Day", "1h 5m", "Bench Press", "1", "60", "8", "", "",
            "felt good, strong", "", "7.5"
        ],
        ["2024-03-11 18:24:00", "Push Day", "1h 5m", "Incline Press", "1", "50", "10", "", "", "", "", ""],
        ["2024-03-11 18:24:00", "Push Day", "1h 5m", "Curl", "1", "notanumber", "10", "", "", "", "", ""]
    ])

    @Test("Strong header is detected")
    func strongDetected() {
        #expect(ImportDetector.detect(headerLine: Self.strongHeader.joined(separator: ",")) == .strong)
    }

    @Test("Strong fixture produces the right workout/exercise/set counts and unit conversion")
    func strongCounts() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.strongCSV))
        #expect(result.source == .strong)
        #expect(result.workouts.count == 1)
        let workout = try #require(result.workouts.first)
        #expect(workout.exercises.count == 2)
        #expect(workout.exercises[0].name == "Bench Press")
        #expect(workout.exercises[0].sets.count == 2)
        #expect(workout.exercises[0].sets[0].kind == .warmup)
        #expect(workout.exercises[0].sets[1].kind == .working)
        #expect(workout.exercises[0].sets[1].weightKg == 60)
        #expect(workout.exercises[0].note == "felt good, strong")
        #expect(result.problems.count == 1)
        #expect(result.problems[0].message.contains("weight"))
    }

    @Test("Strong date and duration parse into startedAt/endedAt")
    func strongDates() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.strongCSV))
        let workout = try #require(result.workouts.first)
        let calendar = Calendar(identifier: .gregorian)
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        let components = calendar.dateComponents(fields, from: workout.startedAt)
        #expect(components.year == 2024 && components.month == 3 && components.day == 11)
        #expect(components.hour == 18 && components.minute == 24)
        let endedAt = try #require(workout.endedAt)
        #expect(endedAt.timeIntervalSince(workout.startedAt) == 3900)
    }

    // MARK: - Hevy

    private static let hevyHeader = [
        "title", "start_time", "end_time", "description", "exercise_title", "superset_id",
        "exercise_notes", "set_index", "set_type", "weight_lbs", "reps", "distance_km",
        "duration_seconds", "rpe"
    ]

    private static let hevyCSV = csv(Self.hevyHeader, [
        [
            "Push Day", "11 Mar 2024, 18:24", "11 Mar 2024, 19:05", "Great session", "Bench Press", "",
            "", "1", "warmup", "88", "10", "", "", ""
        ],
        [
            "Push Day", "11 Mar 2024, 18:24", "11 Mar 2024, 19:05", "Great session", "Bench Press", "",
            "felt good, strong", "2", "normal", "135", "8", "", "", "7.5"
        ],
        [
            "Push Day", "11 Mar 2024, 18:24", "11 Mar 2024, 19:05", "Great session", "Incline Press", "",
            "", "1", "normal", "110", "10", "", "", ""
        ],
        [
            "Push Day", "11 Mar 2024, 18:24", "11 Mar 2024, 19:05", "Great session", "Curl", "",
            "", "1", "normal", "100", "abc", "", "", ""
        ]
    ])

    @Test("Hevy header is detected")
    func hevyDetected() {
        #expect(ImportDetector.detect(headerLine: Self.hevyHeader.joined(separator: ",")) == .hevy)
    }

    @Test("Hevy fixture converts lbs to kg and reports the bad row")
    func hevyCounts() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.hevyCSV))
        #expect(result.source == .hevy)
        #expect(result.workouts.count == 1)
        let workout = try #require(result.workouts.first)
        #expect(workout.exercises.count == 2)
        let bench = try #require(workout.exercises.first)
        #expect(bench.sets.count == 2)
        #expect(bench.sets[0].kind == .warmup)
        #expect(bench.sets[1].kind == .working)
        #expect(abs(bench.sets[1].weightKg - WeightUnit.lb.toKg(135)) < 0.001)
        #expect(bench.note == "felt good, strong")
        #expect(result.problems.count == 1)
    }

    @Test("Hevy start_time parses")
    func hevyDate() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.hevyCSV))
        let workout = try #require(result.workouts.first)
        let calendar = Calendar(identifier: .gregorian)
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        let components = calendar.dateComponents(fields, from: workout.startedAt)
        #expect(components.year == 2024 && components.month == 3 && components.day == 11)
        #expect(components.hour == 18 && components.minute == 24)
    }

    // MARK: - FitNotes

    private static let fitNotesHeader = [
        "Date", "Exercise", "Category", "Weight (kgs)", "Reps", "Distance", "Distance Unit", "Time",
        "Comment"
    ]

    private static let fitNotesCSV = csv(Self.fitNotesHeader, [
        ["2024-03-11", "Squat", "Legs", "100", "5", "", "", "", ""],
        ["2024-03-11", "Squat", "Legs", "102.5", "5", "", "", "", "felt good, strong"],
        ["2024-03-11", "Running", "Cardio", "0", "0", "5", "km", "25:00", ""],
        ["2024-03-11", "Squat", "Legs", "100", "x", "", "", "", ""]
    ])

    @Test("FitNotes header is detected")
    func fitNotesDetected() {
        #expect(ImportDetector.detect(headerLine: Self.fitNotesHeader.joined(separator: ",")) == .fitNotes)
    }

    @Test("FitNotes fixture groups same-day rows into one workout")
    func fitNotesCounts() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.fitNotesCSV))
        #expect(result.source == .fitNotes)
        #expect(result.workouts.count == 1)
        let workout = try #require(result.workouts.first)
        #expect(workout.exercises.count == 2)
        let squat = try #require(workout.exercises.first)
        #expect(squat.sets.count == 2)
        #expect(squat.sets.allSatisfy { $0.kind == .working })
        #expect(squat.note == "felt good, strong")
        let running = workout.exercises[1]
        #expect(running.sets.first?.distanceMeters == 5000)
        #expect(running.sets.first?.durationSeconds == 1500)
        #expect(result.problems.count == 1)
    }

    @Test("FitNotes date-only parses")
    func fitNotesDate() throws {
        let result = try #require(WorkoutImport.parse(csv: Self.fitNotesCSV))
        let workout = try #require(result.workouts.first)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: workout.startedAt)
        #expect(components.year == 2024 && components.month == 3 && components.day == 11)
    }

    // MARK: - Detection failure

    @Test("unrecognized header returns nil")
    func unrecognizedHeader() {
        #expect(ImportDetector.detect(headerLine: "foo,bar,baz") == nil)
        #expect(WorkoutImport.parse(csv: "foo,bar,baz\n1,2,3\n") == nil)
    }
}
