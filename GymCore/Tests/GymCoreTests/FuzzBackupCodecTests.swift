import Foundation
import Testing

@testable import GymCore

/// Property-style fuzzing of `BackupCodec.decode`: a valid export is mutated one path at a time
/// (wrong type, hostile number, hostile string, null, deletion, deep nesting, 10 MB string) and
/// then corrupted at the byte level (truncation, invalid UTF-8, BOM, CRLF). The process surviving
/// is the assertion; every outcome must be either a decoded document or a `CodecError`.
///
/// Seeded with a fixed xorshift so a failure reproduces from its iteration number.
@Suite("Fuzz: BackupCodec", .serialized)
struct FuzzBackupCodecTests {
    static let iterations = 200
    static let seed: UInt64 = 0xB4C4_0001

    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    /// Every table populated, so every key path is a mutation candidate.
    static func fixture() -> BackupDocument {
        let routineID = UUID()
        let workoutID = UUID()
        let planned = BackupPlannedSet(
            order: 0, kind: "working", targetReps: 8, targetRepsHigh: 12, targetWeightKg: 60,
            targetRPE: 8, targetSeconds: 45, targetDistanceMeters: 500
        )
        return BackupDocument(
            exportedAt: date, appVersion: "1.0",
            exercises: [BackupExercise(id: UUID(), seedID: "Barbell_Squat", name: "Squat", createdAt: date)],
            routines: [BackupRoutine(
                id: routineID, name: "Legs", progressionRuleJSON: "{}", createdAt: date, updatedAt: date,
                isArchived: false, importedFromID: UUID(), symbolName: "dumbbell", tint: "coral",
                exercises: [BackupRoutineExercise(
                    order: 0, exerciseSeedID: "Barbell_Squat", exerciseName: "Squat", supersetGroup: 1,
                    restOverrideSeconds: 90, note: "n", progressionRuleJSON: "{}", stallJSON: "{}",
                    trainingMaxKg: 100, excludeFromProgression: false, plannedSets: [planned]
                )]
            )],
            workouts: [BackupWorkout(
                id: workoutID, title: "Legs", startedAt: date, endedAt: date.addingTimeInterval(3600),
                routineID: routineID, routineName: "Legs", bodyweightKg: 80, healthKitID: "hk",
                exercises: [BackupWorkoutExercise(
                    id: UUID(), order: 0, supersetGroup: 1, note: "n", wasSubstitution: false,
                    wasPlannedDeload: false, excludedFromProgression: false, routineID: routineID,
                    exerciseSeedID: "Barbell_Squat", exerciseName: "Squat", sets: [setLog()]
                )]
            )],
            bodyMeasurements: [BackupBodyMeasurement(id: UUID(), date: date, bodyweightKg: 80)],
            equipmentProfiles: [BackupEquipmentProfile(
                id: UUID(), name: "Gym", isActive: true, plateStockKg: [20, 10], plateCounts: [4, 2],
                createdAt: date, seedKey: "gym"
            )],
            preferences: BackupPreferences(),
            programs: [BackupProgram(
                id: UUID(), name: "Block", weeks: 4, startedAt: date, completedAt: date, isActive: true,
                routineIDs: [routineID], createdAt: date,
                programWeeks: [BackupProgramWeek(id: UUID(), index: 1, kind: "normal")]
            )],
            achievements: [BackupAchievement(
                id: UUID(), milestoneID: "first", tier: "bronze", earnedAt: date, workoutID: workoutID
            )],
            schedule: BackupSchedule(scheduleJSON: "{}", updatedAt: date),
            exerciseNotes: [
                BackupExerciseNote(id: UUID(), exerciseName: "Squat", text: "t", createdAt: date)
            ],
            progressPhotos: [
                BackupProgressPhoto(id: UUID(), date: date, bodyweightKg: 80, imageBase64: "AA==")
            ],
            gymCards: [
                BackupGymCard(id: UUID(), name: "Card", value: "123", createdAt: date, lastUsedAt: date)
            ],
            coachInteractions: [BackupCoachInteraction(id: UUID(), rule: "r", fingerprint: "f", date: date)],
            healthImports: healthImports()
        )
    }

    private static func setLog() -> BackupSetLog {
        BackupSetLog(
            id: UUID(), order: 0, kind: "working", weightKg: 60, reps: 8, durationSeconds: 30,
            distanceMeters: 1000, assistanceKg: 5, rpe: 8, isCompleted: true, completedAt: date,
            prescriptionReason: "linear", inclinePercent: 2
        )
    }

    private static func healthImports() -> BackupHealthImport {
        BackupHealthImport(
            imported: [BackupImportedHealthWorkout(
                id: UUID(), healthKitID: "hk", title: "Run", startedAt: date, endedAt: date,
                importedAt: date
            )],
            ignoredHealthKitIDs: ["hk2"]
        )
    }

    static func tree() throws -> FuzzJSON {
        let data = try BackupCodec.encode(fixture())
        return FuzzJSON(any: try JSONSerialization.jsonObject(with: data))
    }

    /// Decoding either succeeds or throws the codec's own error type — never anything else and
    /// never a trap.
    static func check(_ data: Data, label: @autoclosure () -> String) -> BackupDocument? {
        do {
            return try BackupCodec.decode(data)
        } catch is BackupCodec.CodecError {
            return nil
        } catch {
            Issue.record("untyped error for \(label()): \(error)")
            return nil
        }
    }

    @Test("the unmutated fixture decodes")
    func fixtureDecodes() throws {
        let document = try #require(Self.check(try BackupCodec.encode(Self.fixture()), label: "fixture"))
        #expect(document.routines.count == 1)
    }

    @Test("field-by-field mutations never trap and always yield a document or a CodecError")
    func fieldMutations() throws {
        let tree = try Self.tree()
        let paths = tree.paths()
        var rng = FuzzRNG(seed: Self.seed)
        for iteration in 0..<Self.iterations {
            let path = rng.pick(paths)
            var deleted = false
            let mutated = tree.replacing(path: path) { _ in
                if rng.int(6) == 0 { deleted = true; return nil }
                return FuzzValues.leaf(&rng, allowHuge: iteration % 50 == 7)
            }
            let data = Data(mutated.render().utf8)
            _ = Self.check(data, label: "iteration \(iteration) path \(path) deleted=\(deleted)")
        }
    }

    @Test("byte-level corruption of a valid file never traps")
    func byteCorruption() throws {
        let valid = try BackupCodec.encode(Self.fixture())
        var rng = FuzzRNG(seed: Self.seed &+ 1)
        for iteration in 0..<Self.iterations {
            let data = FuzzBytes.corrupt(valid, &rng)
            _ = Self.check(data, label: "corruption \(iteration)")
        }
    }

    @Test("extra keys, duplicate ids and self-referencing ids all still decode")
    func structuralOddities() throws {
        let tree = try Self.tree()
        let extra = tree.addingExtraKey("futureField", value: FuzzValues.deep(depth: 30))
        #expect(Self.check(Data(extra.render().utf8), label: "extra key") != nil)

        var document = Self.fixture()
        let shared = UUID()
        document.routines[0].id = shared
        document.routines[0].importedFromID = shared
        document.routines.append(document.routines[0])
        document.workouts[0].id = shared
        document.workouts[0].routineID = shared
        document.workouts.append(document.workouts[0])
        document.programs?[0].routineIDs = [shared, shared, shared]
        let decoded = try #require(Self.check(try BackupCodec.encode(document), label: "duplicate ids"))
        #expect(decoded.routines.count == 2)
        #expect(decoded.workouts.count == 2)
    }

    @Test("a formatVersion that is huge, negative, fractional or absent is a typed error")
    func formatVersionEdges() throws {
        let tree = try Self.tree()
        for token in ["9223372036854775807", "9223372036854775808", "-1", "1.5", "NaN", "\"1\"", "null"] {
            let mutated = tree.replacing(path: [.key("formatVersion")]) { _ in .raw(token) }
            _ = Self.check(Data(mutated.render().utf8), label: "formatVersion \(token)")
        }
        let missing = tree.replacing(path: [.key("formatVersion")]) { _ in nil }
        #expect(Self.check(Data(missing.render().utf8), label: "no formatVersion") == nil)
    }

    @Test("a 10 MB string in every text field decodes without trapping")
    func hugeStrings() throws {
        var document = Self.fixture()
        let huge = String(repeating: "q", count: FuzzValues.hugeStringLength)
        document.routines[0].notes = huge
        document.exercises[0].instructions = huge
        document.schedule = BackupSchedule(scheduleJSON: huge, updatedAt: Self.date)
        let decoded = try #require(Self.check(try BackupCodec.encode(document), label: "huge"))
        #expect(decoded.routines[0].notes.count == FuzzValues.hugeStringLength)
    }
}
