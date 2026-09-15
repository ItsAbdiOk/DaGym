import Foundation
import Testing

@testable import GymCore

@Suite("BackupCodec")
struct BackupCodecTests {
    private func sampleDocument() -> BackupDocument {
        let exerciseID = UUID()
        let routineID = UUID()
        let workoutID = UUID()
        let exercise = BackupExercise(
            id: exerciseID, seedID: nil, name: "Zercher Squat", primaryMuscles: ["quads"],
            equipment: "barbell", isCustom: true, isFavorite: true, incrementKg: 2.5, restSeconds: 150
        )
        let plannedSet = BackupPlannedSet(order: 0, kind: "working", targetReps: 8, targetWeightKg: 60)
        let routineExercise = BackupRoutineExercise(
            order: 0, exerciseSeedID: nil, exerciseName: "Zercher Squat",
            progressionRuleJSON: "{\"linear\":{\"incrementKg\":2.5}}", stallJSON: "{\"misses\":1}",
            trainingMaxKg: 120, plannedSets: [plannedSet]
        )
        let routine = BackupRoutine(id: routineID, name: "Legs", exercises: [routineExercise])
        let setLog = BackupSetLog(
            id: UUID(), order: 0, kind: "working", weightKg: 60, reps: 8, isCompleted: true
        )
        let workoutExercise = BackupWorkoutExercise(
            id: UUID(), order: 0, wasPlannedDeload: true, exerciseName: "Zercher Squat", sets: [setLog]
        )
        let workout = BackupWorkout(
            id: workoutID, title: "Legs", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600), exercises: [workoutExercise]
        )
        let measurement = BackupBodyMeasurement(
            id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000), bodyweightKg: 82
        )
        let equipment = BackupEquipmentProfile(
            id: UUID(), name: "Gym", isActive: true, availableEquipment: ["barbell", "dumbbell"],
            plateStockKg: [20, 10], plateCounts: [4, 4]
        )
        return BackupDocument(
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000), appVersion: "1.0 (1)",
            exercises: [exercise], routines: [routine], workouts: [workout],
            bodyMeasurements: [measurement], equipmentProfiles: [equipment],
            preferences: BackupPreferences()
        )
    }

    /// Spot checks on a small document. The *exhaustive* "nothing is lost" guarantee lives in
    /// `BackupCoverageTests`, which walks the model with `Mirror` instead of listing fields by
    /// hand — this one only has to stay readable.
    @Test("round trip preserves the headline fields")
    func roundTrip() throws {
        let document = sampleDocument()
        let data = try BackupCodec.encode(document)
        let decoded = try BackupCodec.decode(data)

        #expect(decoded.formatVersion == BackupDocument.currentFormatVersion)
        #expect(decoded.exercises.map(\.id) == document.exercises.map(\.id))
        #expect(decoded.exercises.first?.isFavorite == true)
        #expect(decoded.routines.first?.name == "Legs")
        #expect(decoded.routines.first?.exercises.first?.plannedSets.first?.targetWeightKg == 60)
        #expect(decoded.workouts.first?.id == document.workouts.first?.id)
        #expect(decoded.workouts.first?.exercises.first?.sets.first?.reps == 8)
        #expect(decoded.bodyMeasurements.first?.bodyweightKg == 82)
        #expect(decoded.equipmentProfiles.first?.name == "Gym")
        #expect(decoded.preferences.weightUnit == "kg")
        let decodedRoutineExercise = decoded.routines.first?.exercises.first
        #expect(decodedRoutineExercise?.progressionRuleJSON == "{\"linear\":{\"incrementKg\":2.5}}")
        #expect(decodedRoutineExercise?.stallJSON == "{\"misses\":1}")
        #expect(decodedRoutineExercise?.trainingMaxKg == 120)
        #expect(decoded.workouts.first?.exercises.first?.wasPlannedDeload == true)
    }

    @Test("a backup exported before the engine-memory fields existed still decodes")
    func decodesBackupsFromBeforeEngineMemoryFields() throws {
        let document = sampleDocument()
        let data = try BackupCodec.encode(document)
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        var routines = json?["routines"] as? [[String: Any]]
        var exercises = routines?[0]["exercises"] as? [[String: Any]]
        exercises?[0]["progressionRuleJSON"] = nil
        exercises?[0]["stallJSON"] = nil
        exercises?[0]["trainingMaxKg"] = nil
        routines?[0]["exercises"] = exercises
        json?["routines"] = routines
        var workouts = json?["workouts"] as? [[String: Any]]
        var workoutExercises = workouts?[0]["exercises"] as? [[String: Any]]
        workoutExercises?[0]["wasPlannedDeload"] = nil
        workouts?[0]["exercises"] = workoutExercises
        json?["workouts"] = workouts
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)

        let decoded = try BackupCodec.decode(mutated)
        #expect(decoded.routines.first?.exercises.first?.stallJSON == nil)
        #expect(decoded.workouts.first?.exercises.first?.wasPlannedDeload == nil)
    }

    @Test("encoded JSON uses sorted keys and ISO 8601 dates")
    func stableFormat() throws {
        let document = sampleDocument()
        let data = try BackupCodec.encode(document)
        let text = String(bytes: data, encoding: .utf8) ?? ""
        #expect(text.contains("\"appVersion\""))
        // Sorted keys: "appVersion" sorts before "bodyMeasurements" sorts before "equipmentProfiles".
        let appVersionIndex = try #require(text.range(of: "\"appVersion\"")?.lowerBound)
        let bodyIndex = try #require(text.range(of: "\"bodyMeasurements\"")?.lowerBound)
        #expect(appVersionIndex < bodyIndex)
        #expect(text.contains("T")) // ISO 8601 timestamp marker
    }

    @Test("unknown future fields are ignored")
    func unknownFieldsIgnored() throws {
        let document = sampleDocument()
        let data = try BackupCodec.encode(document)
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["fromTheFuture"] = "some field a later app version added"
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)
        let decoded = try BackupCodec.decode(mutated)
        #expect(decoded.appVersion == document.appVersion)
    }

    @Test("a file needing a newer reader than this build throws a typed error")
    func formatVersionMismatch() throws {
        let document = sampleDocument()
        let data = try BackupCodec.encode(document)
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["formatVersion"] = BackupDocument.currentFormatVersion + 1
        json?["minimumReaderVersion"] = BackupDocument.currentFormatVersion + 1
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)

        #expect(throws: BackupCodec.CodecError.unsupportedFormatVersion(
            found: BackupDocument.currentFormatVersion + 1, supported: BackupDocument.currentFormatVersion
        )) {
            try BackupCodec.decode(mutated)
        }
    }

    @Test("a newer file without a minimumReaderVersion stamp is treated as needing its own version")
    func newerFileWithoutStampIsRejected() throws {
        let data = try BackupCodec.encode(sampleDocument())
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["formatVersion"] = BackupDocument.currentFormatVersion + 1
        json?.removeValue(forKey: "minimumReaderVersion")
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)

        #expect(throws: BackupCodec.CodecError.unsupportedFormatVersion(
            found: BackupDocument.currentFormatVersion + 1, supported: BackupDocument.currentFormatVersion
        )) {
            try BackupCodec.decode(mutated)
        }
    }

    @Test("a newer file this build may still read decodes and names the sections it can't read")
    func newerReadableFileReportsUnknownSections() throws {
        let data = try BackupCodec.encode(sampleDocument())
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["formatVersion"] = BackupDocument.currentFormatVersion + 1
        json?["minimumReaderVersion"] = BackupDocument.currentFormatVersion
        json?["sections"] = BackupDocument.requiredSections + ["programs", "sleepLogs"]
        json?["programs"] = [] as [Any]
        json?["sleepLogs"] = [["id": UUID().uuidString, "hours": 7.5]]
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)

        let decoded = try BackupCodec.decode(mutated)
        #expect(decoded.formatVersion == BackupDocument.currentFormatVersion + 1)
        #expect(decoded.unreadableSections == ["sleepLogs"])
        #expect(decoded.absentSections.contains("progressPhotos"))
        #expect(!decoded.absentSections.contains("programs"))
    }

    @Test("a format-1 file (no stamp, no sections list) decodes with nothing reported unreadable")
    func formatOneFileDecodes() throws {
        let data = try BackupCodec.encode(sampleDocument())
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["formatVersion"] = 1
        json?.removeValue(forKey: "minimumReaderVersion")
        json?.removeValue(forKey: "sections")
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)

        let decoded = try BackupCodec.decode(mutated)
        #expect(decoded.formatVersion == 1)
        #expect(decoded.minimumReaderVersion == nil)
        #expect(decoded.unreadableSections.isEmpty)
        #expect(decoded.absentSections == BackupDocument.optionalSections)
    }

    @Test("the sections stamp lists exactly the optional sections the document carries")
    func sectionsStamp() {
        var document = sampleDocument()
        document.programs = []
        document.progressPhotos = nil
        let stamped = BackupDocument(
            exportedAt: document.exportedAt, appVersion: document.appVersion,
            preferences: document.preferences, programs: [], schedule: BackupSchedule(updatedAt: Date())
        )
        #expect(stamped.sections == BackupDocument.requiredSections + ["programs", "schedule"])
        #expect(stamped.minimumReaderVersion == BackupDocument.minimumReaderVersion)
        #expect(stamped.absentSections.contains("progressPhotos"))
    }

    @Test("format-1 JSON-in-JSON fields still resolve to typed values")
    func legacyStringsResolve() throws {
        let routine = BackupRoutine(
            id: UUID(), name: "Legs", progressionRuleJSON: #"{"linear":{"incrementKg":5}}"#,
            exercises: [BackupRoutineExercise(
                order: 0, exerciseName: "Squat",
                progressionRuleJSON: #"{"timed":{"stepSeconds":10}}"#,
                stallJSON: #"{"consecutiveMisses":2,"lastWeightKg":100}"#
            )]
        )
        #expect(routine.resolvedRule == .linear(incrementKg: 5))
        #expect(routine.exercises[0].resolvedRule == .timed(stepSeconds: 10))
        #expect(routine.exercises[0].resolvedStall.consecutiveMisses == 2)
        #expect(routine.exercises[0].resolvedStall.lastWeightKg == 100)

        let blank = BackupRoutineExercise(order: 0, exerciseName: "Squat", stallJSON: "{}")
        #expect(blank.resolvedStall == StallState())
        #expect(blank.resolvedRule == nil)

        let planned = WeeklySchedule(days: [.monday: UUID()])
        let scheduleJSON = try #require(String(data: JSONEncoder().encode(planned), encoding: .utf8))
        let schedule = BackupSchedule(scheduleJSON: scheduleJSON, updatedAt: Date())
        #expect(schedule.resolvedSchedule == planned)
        #expect(BackupSchedule(updatedAt: Date()).resolvedSchedule == nil)
    }

    @Test("nested values win over legacy strings, and a legacy string that won't parse reads as absent")
    func nestedValuesWin() {
        let slot = BackupRoutineExercise(
            order: 0, exerciseName: "Squat", rule: .linear(incrementKg: 2.5),
            stall: StallState(consecutiveMisses: 1), progressionRuleJSON: "not json", stallJSON: "nope"
        )
        #expect(slot.resolvedRule == .linear(incrementKg: 2.5))
        #expect(slot.resolvedStall.consecutiveMisses == 1)
        let broken = BackupRoutineExercise(order: 0, exerciseName: "Squat", progressionRuleJSON: "not json")
        #expect(broken.resolvedRule == nil)
    }

    @Test("plate stock resolves from pairs, or from the parallel arrays zipped defensively")
    func plateStockResolves() {
        let pairs = BackupEquipmentProfile(
            id: UUID(), name: "Gym", plateStock: [BackupPlateStock(weightKg: 20, count: 4)],
            plateStockKg: [25, 20], plateCounts: [2, 2]
        )
        #expect(pairs.resolvedPlateStock == [PlateStock(weightKg: 20, count: 4)])

        let legacy = BackupEquipmentProfile(
            id: UUID(), name: "Gym", plateStockKg: [25, 20, 10], plateCounts: [2, 4]
        )
        #expect(legacy.resolvedPlateStock == [
            PlateStock(weightKg: 25, count: 2), PlateStock(weightKg: 20, count: 4)
        ])
    }

    @Test("corrupted JSON throws a decoding error")
    func corruptedJSON() throws {
        let garbage = Data("not json at all {{{".utf8)
        #expect(throws: BackupCodec.CodecError.self) {
            try BackupCodec.decode(garbage)
        }
    }
}
