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

    @Test("round trip preserves every field")
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

    @Test("formatVersion mismatch throws a typed error")
    func formatVersionMismatch() throws {
        let document = sampleDocument()
        let data = try BackupCodec.encode(document)
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["formatVersion"] = BackupDocument.currentFormatVersion + 1
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)

        #expect(throws: BackupCodec.CodecError.unsupportedFormatVersion(
            found: BackupDocument.currentFormatVersion + 1, supported: BackupDocument.currentFormatVersion
        )) {
            try BackupCodec.decode(mutated)
        }
    }

    @Test("corrupted JSON throws a decoding error")
    func corruptedJSON() throws {
        let garbage = Data("not json at all {{{".utf8)
        #expect(throws: BackupCodec.CodecError.self) {
            try BackupCodec.decode(garbage)
        }
    }
}
