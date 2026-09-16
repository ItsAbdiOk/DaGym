import Foundation
import Testing

// `String(decoding:as:)` is deliberate: the corrupted bytes are the input under test.
// swiftlint:disable optional_data_string_conversion

@testable import GymCore

/// Property-style fuzzing of the three CSV importers through `WorkoutImport.parse`. A valid
/// export of each format is mutated cell by cell with the hostile-number/string vocabulary, then
/// structurally (mismatched column counts, a quote that never closes, CRLF, BOM, invalid UTF-8,
/// random bytes), and every set that comes out must sit inside `ImportLimits`. A 100k-row file
/// checks the parse stays linear and never traps on volume.
@Suite("Fuzz: CSV importers", .serialized)
struct FuzzCSVImportTests {
    static let iterations = FuzzIterations.count
    static let seed: UInt64 = 0xC5F0_0003

    struct Fixture {
        var source: ImportSource
        var header: [String]
        var rows: [[String]]

        func text(lineEnding: String = "\n") -> String {
            ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: lineEnding) + lineEnding
        }
    }

    static let day1 = "2024-03-11 18:24:00"
    static let day2 = "2024-03-13 07:00:00"

    static let strong = Fixture(
        source: .strong,
        header: [
            "Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight", "Weight Unit",
            "Reps", "Distance", "Distance Unit", "Seconds", "Notes", "Workout Notes", "RPE"
        ],
        rows: [
            [day1, "Push", "1h 5m", "Bench Press", "1", "60", "kg", "8", "0", "m", "0", "", "", "8"],
            [day1, "Push", "1h 5m", "Bench Press", "W1", "40", "kg", "10", "0", "m", "0", "", "", ""],
            [day1, "Push", "1h 5m", "Run", "1", "0", "kg", "0", "2.5", "km", "900", "", "", ""],
            [day2, "Pull", "45m", "Row", "Dropset", "50", "lbs", "12", "0", "m", "0", "n", "w", "9"]
        ]
    )

    /// Hevy dates carry a comma, so they travel quoted.
    static let start = "\"11 Mar 2024, 18:24\""
    static let end = "\"11 Mar 2024, 19:30\""

    static let hevy = Fixture(
        source: .hevy,
        header: [
            "title", "start_time", "end_time", "description", "exercise_title", "superset_id",
            "exercise_notes", "set_index", "set_type", "weight_kg", "reps", "distance_km",
            "duration_seconds", "rpe"
        ],
        rows: [
            ["Push", start, end, "", "Bench Press", "", "", "0", "normal", "60", "8", "", "", "8"],
            ["Push", start, end, "", "Bench Press", "1", "", "1", "warmup", "40", "10", "", "", ""],
            ["Push", start, end, "", "Run", "", "", "0", "normal", "", "", "2.5", "900", ""],
            ["Pull", "\"13 Mar 2024, 07:00\"", "", "", "Row", "2", "n", "0", "dropset", "50", "12", "", "",
             "9"]
        ]
    )

    static let fitNotes = Fixture(
        source: .fitNotes,
        header: [
            "Date", "Exercise", "Category", "Weight (kgs)", "Weight Unit", "Reps", "Distance",
            "Distance Unit", "Time", "Comment", "Kind"
        ],
        rows: [
            ["2024-03-11", "Bench Press", "Chest", "60", "kg", "8", "", "", "", "", ""],
            ["2024-03-11", "Bench Press", "Chest", "40", "kg", "10", "", "", "", "", "Warm-Up"],
            ["2024-03-11", "Run", "Cardio", "", "", "", "2.5", "km", "0:15:00", "", ""],
            ["2024-03-13", "Row", "Back", "50", "kg", "12", "", "", "", "c", ""]
        ]
    )

    static let fixtures = [strong, hevy, fitNotes]

    // MARK: - Bounds

    static func assertBounds(_ result: ImportResult, label: @autoclosure () -> String) {
        for workout in result.workouts {
            #expect(!workout.exercises.isEmpty, "\(label())")
            if let end = workout.endedAt { #expect(end >= workout.startedAt, "\(label())") }
            for exercise in workout.exercises {
                #expect(!exercise.name.isEmpty, "\(label())")
                #expect(exercise.note.count <= ImportLimits.maxTextLength, "\(label())")
                #expect(!exercise.sets.isEmpty, "\(label())")
                for set in exercise.sets {
                    #expect(set.weightKg.isFinite && set.weightKg >= 0, "\(label())")
                    #expect(set.weightKg <= ImportLimits.maxWeightKg, "\(label())")
                    #expect((0...ImportLimits.maxReps).contains(set.reps), "\(label())")
                    let duration = set.durationSeconds ?? 1
                    #expect(duration > 0 && duration <= ImportLimits.maxDurationSeconds, "\(label())")
                    let distance = set.distanceMeters ?? 1
                    #expect(distance.isFinite && distance > 0, "\(label())")
                    #expect(distance <= ImportLimits.maxDistanceMeters, "\(label())")
                    #expect(set.rpe.map { $0.isFinite && $0 > 0 && $0 <= 10 } ?? true, "\(label())")
                    let measured = set.weightKg != 0 || set.reps != 0 || set.durationSeconds != nil
                        || set.distanceMeters != nil
                    #expect(measured, "an all-zero set was imported: \(label())")
                }
            }
        }
    }

    static func parseAndCheck(_ csv: String, label: @autoclosure () -> String) {
        guard let result = WorkoutImport.parse(csv: csv, assumedWeightUnit: .lb) else { return }
        assertBounds(result, label: label())
    }

    // MARK: - Tests

    @Test("the three fixtures parse cleanly", arguments: [0, 1, 2])
    func fixturesParse(index: Int) throws {
        let fixture = Self.fixtures[index]
        let result = try #require(WorkoutImport.parse(csv: fixture.text()))
        #expect(result.source == fixture.source)
        #expect(result.workouts.count == 2)
        #expect(result.problems.isEmpty)
        Self.assertBounds(result, label: fixture.source.rawValue)
    }

    @Test("cell-by-cell hostile values never trap and every imported set is within limits")
    func cellMutations() {
        var rng = FuzzRNG(seed: Self.seed)
        for iteration in 0..<Self.iterations {
            var fixture = rng.pick(Self.fixtures)
            let edits = 1 + rng.int(4)
            for _ in 0..<edits {
                let row = rng.int(fixture.rows.count)
                let column = rng.int(fixture.header.count)
                fixture.rows[row][column] = Self.hostileCell(&rng)
            }
            Self.parseAndCheck(fixture.text(), label: "cell \(iteration) \(fixture.source)")
        }
    }

    static func hostileCell(_ rng: inout FuzzRNG) -> String {
        switch rng.int(5) {
        case 0: return rng.pick(FuzzValues.numberTokens)
        case 1: return rng.pick(FuzzValues.stringTokens).replacingOccurrences(of: "\n", with: " ")
        case 2: return rng.pick(["1:2:3:4", "99:99", "-1:00", "1h", "999999999999h", "0h 0m", "1e5s", "x"])
        case 3: return rng.pick(["kg", "lbs", "stone", "", "KG", "mi", "furlong"])
        default:
            return rng.pick(["2024-99-99", "0000-00-00", "99999999-01-01 00:00:00", "", "32 Jan 2024, 25:61"])
        }
    }

    /// The structural damage vocabulary; each takes the fixture and its rendered text.
    static let damages: [@Sendable (Fixture, String, inout FuzzRNG) -> String] = [
        { fixture, _, rng in withColumnCountsMismatched(fixture, &rng) },
        { _, text, _ in text.replacingOccurrences(of: "Bench Press", with: "\"Bench, Press") },
        { _, text, _ in "\u{FEFF}" + text },
        { _, text, _ in text.replacingOccurrences(of: ",", with: ",\"\"\"") },
        { _, text, rng in String(text.prefix(rng.int(text.count + 1))) },
        { _, text, _ in text.replacingOccurrences(of: "\n", with: "\r") },
        { fixture, _, _ in
            fixture.header.joined(separator: ",") + "\n" + String(repeating: ",", count: 40) + "\n"
        },
        { _, text, rng in String(decoding: FuzzBytes.corrupt(Data(text.utf8), &rng), as: UTF8.self) }
    ]

    @Test("structural damage (column counts, unclosed quotes, CRLF, BOM, bad bytes) never traps")
    func structuralMutations() {
        var rng = FuzzRNG(seed: Self.seed &+ 1)
        for iteration in 0..<Self.iterations {
            let fixture = rng.pick(Self.fixtures)
            let text = fixture.text(lineEnding: rng.bool() ? "\n" : "\r\n")
            let damage = rng.int(Self.damages.count)
            let damaged = Self.damages[damage](fixture, text, &rng)
            Self.parseAndCheck(damaged, label: "structure \(iteration) \(fixture.source) damage \(damage)")
        }
    }

    private static func withColumnCountsMismatched(_ fixture: Fixture, _ rng: inout FuzzRNG) -> String {
        var fixture = fixture
        for index in fixture.rows.indices {
            switch rng.int(3) {
            case 0: fixture.rows[index] = Array(fixture.rows[index].prefix(rng.int(fixture.header.count)))
            case 1: fixture.rows[index] += Array(repeating: "extra", count: 1 + rng.int(5))
            default: break
            }
        }
        if rng.bool() { fixture.header = Array(fixture.header.prefix(rng.int(fixture.header.count + 1))) }
        return fixture.text()
    }

    @Test("an unclosed quote swallowing the rest of the file still yields a result or nil, never a trap")
    func unclosedQuote() {
        for fixture in Self.fixtures {
            let text = fixture.text().replacingOccurrences(of: "60", with: "\"60")
            Self.parseAndCheck(text, label: "unclosed \(fixture.source)")
            #expect(CSVParser.parse("\"never closed").count == 1)
            #expect(CSVParser.parse("\"").first == [""])
        }
    }

    @Test("invalid UTF-8 and control bytes in every cell are repaired, not fatal")
    func invalidBytes() {
        let bad = Data([0xFF, 0xC0, 0x80, 0xED, 0xA0, 0x80, 0x00, 0x1F])
        for fixture in Self.fixtures {
            var text = fixture.text()
            text = text.replacingOccurrences(of: "Bench Press", with: String(decoding: bad, as: UTF8.self))
            Self.parseAndCheck(text, label: "bytes \(fixture.source)")
        }
    }

    @Test("100k rows parse into bounded workouts without trapping")
    func hundredThousandRows() throws {
        var rng = FuzzRNG(seed: Self.seed &+ 2)
        var lines = [Self.strong.header.joined(separator: ",")]
        lines.reserveCapacity(100_001)
        for index in 0..<100_000 {
            var row = Self.strong.rows[index % Self.strong.rows.count]
            let day = 1 + (index / 40) % 28
            row[0] = String(format: "2024-%02d-%02d 18:24:00", 1 + (index / 1120) % 12, day)
            if index % 97 == 0 { row[rng.int(row.count)] = Self.hostileCell(&rng) }
            lines.append(row.joined(separator: ","))
        }
        let csv = lines.joined(separator: "\n") + "\n"
        let result = try #require(WorkoutImport.parse(csv: csv))
        #expect(result.workouts.count > 100)
        Self.assertBounds(result, label: "100k")
    }
}

// swiftlint:enable optional_data_string_conversion
