import Foundation
import Testing

@testable import GymCore

/// Pace and speed maths, the cardio PR kinds, the codec fields and the cardio voice grammar.
/// Every expected number is hand-derived: 5 km in 25:30 is 1530 s / 5 = 306 s/km = 5:06; the
/// same run in miles is 5000 / 1609.344 = 3.1069 mi, 1530 / 3.1069 = 492.5 s/mi = 8:12 (rounded
/// to the nearest second), and 3.1069 / (1530 / 3600) = 7.31 mi/h.
@Suite("Cardio")
struct CardioTests {
    private static let day1 = Date(timeIntervalSince1970: 1_000_000)
    private static let day2 = Date(timeIntervalSince1970: 1_100_000)

    // MARK: - Pace maths

    @Test("5 km in 25:30 is 5:06 /km and 11.8 km/h")
    func paceInKm() {
        let pace = CardioPace.secondsPerUnit(distanceMeters: 5000, durationSeconds: 1530, unit: .km)
        #expect(pace == 306)
        #expect(CardioPace.formatPace(distanceMeters: 5000, durationSeconds: 1530, unit: .km) == "5:06 /km")
        #expect(CardioPace.formatSpeed(distanceMeters: 5000, durationSeconds: 1530, unit: .km) == "11.8 km/h")
    }

    @Test("the same run in miles is 8:12 /mi and 7.3 mi/h")
    func paceInMiles() throws {
        let pace = try #require(
            CardioPace.secondsPerUnit(distanceMeters: 5000, durationSeconds: 1530, unit: .mi)
        )
        #expect(abs(pace - 492.5) < 0.1)
        #expect(CardioPace.formatPace(distanceMeters: 5000, durationSeconds: 1530, unit: .mi) == "8:12 /mi")
        #expect(CardioPace.formatSpeed(distanceMeters: 5000, durationSeconds: 1530, unit: .mi) == "7.3 mi/h")
    }

    @Test("no distance or no time means no pace, not a zero or an infinity")
    func degeneratePace() {
        #expect(CardioPace.secondsPerUnit(distanceMeters: 0, durationSeconds: 1530, unit: .km) == nil)
        #expect(CardioPace.secondsPerUnit(distanceMeters: 5000, durationSeconds: 0, unit: .km) == nil)
        #expect(CardioPace.formatPace(distanceMeters: 0, durationSeconds: 0, unit: .mi) == nil)
        #expect(CardioPace.unitsPerHour(distanceMeters: -5, durationSeconds: 10, unit: .km) == nil)
    }

    @Test("a sub-metre distance has no pace, and whole seconds are clamped rather than trapping")
    func subMetreDistanceHasNoPace() {
        #expect(CardioPace.secondsPerUnit(distanceMeters: 0.001, durationSeconds: 300, unit: .km) == nil)
        #expect(CardioPace.unitsPerHour(distanceMeters: 0.5, durationSeconds: 300, unit: .km) == nil)
        #expect(CardioPace.formatPace(distanceMeters: 0.001, durationSeconds: 300, unit: .km) == nil)
        #expect(CardioPace.secondsPerUnit(distanceMeters: 1, durationSeconds: 300, unit: .km) == 300_000)
        #expect(CardioPace.wholeSeconds(.nan) == 0)
        #expect(CardioPace.wholeSeconds(.infinity) == CardioPace.maxClockSeconds)
        #expect(CardioPace.wholeSeconds(-5) == 0)
        #expect(CardioPace.wholeSeconds(305.6) == 306)
    }

    @Test("the clock grows an hours field past 60 minutes")
    func clock() {
        #expect(CardioPace.clock(1530) == "25:30")
        #expect(CardioPace.clock(3725) == "1:02:05")
        #expect(CardioPace.clock(-3) == "0:00")
    }

    @Test("distance units convert and format in both directions; lb lifters default to miles")
    func distanceUnits() {
        #expect(DistanceUnit.km.formatWithSymbol(meters: 5000) == "5.00 km")
        #expect(DistanceUnit.mi.formatWithSymbol(meters: 5000) == "3.11 mi")
        #expect(abs(DistanceUnit.mi.toMeters(3) - 4828.032) < 0.001)
        #expect(DistanceUnit.matching(.lb) == .mi)
        #expect(DistanceUnit.matching(.kg) == .km)
    }

    // MARK: - Personal records

    private func run(meters: Double?, seconds: Int?, date: Date = day1) -> PerformedSet {
        PerformedSet(
            kind: .working, weightKg: 0, reps: 0, durationSeconds: seconds, date: date,
            distanceMeters: meters
        )
    }

    @Test("a first run banks longest distance and fastest pace; a shorter, slower one beats neither")
    func cardioRecords() {
        let first = PersonalRecords.evaluate(
            newSets: [run(meters: 5000, seconds: 1530)], existing: [], workoutDate: Self.day1
        )
        let longest = first.first { $0.kind == .longestDistance }
        let fastest = first.first { $0.kind == .fastestPace }
        #expect(longest?.value == 5000)
        #expect(fastest?.value == 306)
        // Nothing else fires for a set with no load and no reps.
        #expect(first.count == 2)

        let second = PersonalRecords.evaluate(
            newSets: [run(meters: 3000, seconds: 1000, date: Self.day2)], existing: first,
            workoutDate: Self.day2
        )
        #expect(second.isEmpty)
    }

    @Test("a sprint under 1 km cannot take the pace record; a run with no time has no pace")
    func paceFloor() {
        let sprint = PersonalRecords.evaluate(
            newSets: [run(meters: 200, seconds: 30), run(meters: 2000, seconds: nil)], existing: [],
            workoutDate: Self.day1
        )
        #expect(sprint.contains { $0.kind == .longestDistance && $0.value == 2000 })
        #expect(!sprint.contains { $0.kind == .fastestPace })
    }

    @Test("record lines read in the lifter's distance unit")
    func recordLines() {
        let longest = PersonalRecord(
            kind: .longestDistance, value: 5000, weightKg: 0, reps: 0, date: Self.day1
        )
        let fastest = PersonalRecord(kind: .fastestPace, value: 306, weightKg: 0, reps: 0, date: Self.day1)
        #expect(PersonalRecords.formatLine(longest) == "Longest 5.00 km")
        #expect(PersonalRecords.formatLine(longest, distanceUnit: .mi) == "Longest 3.11 mi")
        #expect(PersonalRecords.formatLine(fastest) == "Fastest 5:06 /km over 1.0 km+")
        #expect(PersonalRecords.formatLine(fastest, distanceUnit: .mi) == "Fastest 8:12 /mi over 0.6 mi+")
    }

    @Test("the stored raw values of the older kinds are untouched by the new cases")
    func rawValuesStable() {
        #expect(PRKind.allCases.map(\.rawValue) == [
            "e1rm", "maxWeight", "maxRepsAtWeight", "volume", "longestHold", "leastAssistance",
            "longestDistance", "fastestPace"
        ])
    }

    // MARK: - Codecs

    @Test("a planned distance and an incline survive the backup codec")
    func backupRoundTrip() throws {
        let planned = BackupPlannedSet(
            order: 0, kind: "working", targetSeconds: 1500, targetDistanceMeters: 5000
        )
        let log = BackupSetLog(
            id: UUID(), order: 0, kind: "working", durationSeconds: 1530, distanceMeters: 5000,
            isCompleted: true, inclinePercent: 1.5
        )
        let plannedData = try JSONEncoder().encode(planned)
        let logData = try JSONEncoder().encode(log)
        let decodedPlanned = try JSONDecoder().decode(BackupPlannedSet.self, from: plannedData)
        #expect(decodedPlanned.targetDistanceMeters == 5000)
        #expect(try JSONDecoder().decode(BackupSetLog.self, from: logData).inclinePercent == 1.5)
    }

    @Test("a plan's distance target survives the share codec and a non-positive one is dropped")
    func planRoundTrip() throws {
        let set = PlanSet(order: 0, kind: "working", targetSeconds: 1500, targetDistanceMeters: 5000)
        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(PlanSet.self, from: data).targetDistanceMeters == 5000)
        let junk = PlanSet(order: 0, kind: "working", targetDistanceMeters: -1).sanitised()
        #expect(junk.targetDistanceMeters == nil)
    }

    // MARK: - Voice

    private static let runID = UUID()

    private func treadmillContext() -> ParseContext {
        var context = VoiceCommandParserFixtures.benchContext()
        context.onDeck = ParseContext.OnDeckSet(
            exerciseID: Self.runID, name: "Treadmill Run", loggingStyle: .cardio, grid: .free
        )
        context.sessionExercises.append(ParseContext.ExerciseCandidate(
            id: Self.runID, name: "Treadmill Run", equipment: "treadmill", isInSession: true,
            loggingStyle: .cardio, grid: .free
        ))
        return context
    }

    private func values(_ text: String, context: ParseContext) -> LogSetSpec.SetValues? {
        let result = VoiceCommandParser.parse(text, context: context)
        guard case .logSet(let spec) = result.commands.first else { return nil }
        #expect(result.matchedPattern == "cardio")
        return spec.sets.first
    }

    @Test("\"five k in twenty five thirty\" is 5000 m in 25:30 on the on-deck run")
    func fiveK() {
        let set = values("five k in twenty five thirty", context: treadmillContext())
        #expect(set?.distanceMeters == 5000)
        #expect(set?.durationSeconds == 1530)
        #expect(set?.reps == nil)
        #expect(set?.weightKg == nil)
    }

    @Test("\"ran 3 miles in 28 minutes\" is 4828 m in 28:00, even with bench on deck")
    func threeMiles() throws {
        let context = VoiceCommandParserFixtures.benchContext()
        let set = try #require(values("ran 3 miles in 28 minutes", context: context))
        #expect(abs((set.distanceMeters ?? 0) - 4828.032) < 0.001)
        #expect(set.durationSeconds == 28 * 60)
    }

    @Test("a bare \"25:30\" on a cardio row is a time with no distance")
    func bareClock() {
        let set = values("25:30", context: treadmillContext())
        #expect(set?.durationSeconds == 1530)
        #expect(set?.distanceMeters == nil)
    }

    @Test("\"eight at sixty\" on a cardio row is rejected as a tracking-style mismatch")
    func cardioRejectsLoad() {
        let result = VoiceCommandParser.parse("eight at sixty", context: treadmillContext())
        let validated = LogCommandValidator.validate(result.commands, in: treadmillContext())
        #expect(validated == .failure(.trackingStyleMismatch))
    }

    @Test("a two-hour run passes the validator's cardio duration bound")
    func longRunAllowed() throws {
        let spec = LogSetSpec(sets: [LogSetSpec.SetValues(durationSeconds: 7200, distanceMeters: 20_000)])
        let validated = LogCommandValidator.validate([.logSet(spec)], in: treadmillContext())
        guard case .success(let commands) = validated, case .logSet(let out) = commands.first?.command else {
            Issue.record("expected the run to validate, got \(validated)")
            return
        }
        #expect(out.sets.first?.distanceMeters == 20_000)
    }
}
