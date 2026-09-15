import Foundation
import Testing

@testable import GymCore

@Suite("PlanCodec")
struct PlanCodecTests {
    private func sampleDocument() -> PlanDocument {
        let customID = UUID()
        let routineID = UUID()
        let custom = PlanExercise(
            id: customID, name: "Zercher Squat", primaryMuscles: ["quads"], equipment: "barbell",
            incrementKg: 2.5, restSeconds: 150, instructions: "Cradle the bar in your elbows."
        )
        let seededSet = PlanSet(order: 0, kind: "working", targetReps: 8, targetWeightKg: 60)
        let seededSlot = PlanRoutineExercise(
            order: 0, exerciseSeedID: "bench-press", exerciseName: "Bench Press", sets: [seededSet]
        )
        let customSet = PlanSet(order: 0, kind: "working", targetReps: 6)
        let customSlot = PlanRoutineExercise(
            order: 1, exerciseName: "Zercher Squat", supersetGroup: 1, sets: [customSet]
        )
        let routine = PlanRoutine(
            id: routineID, name: "Legs", ruleJSON: "{\"linear\":{\"incrementKg\":2.5}}",
            exercises: [seededSlot, customSlot]
        )
        let weeks = [PlanProgramWeek(index: 1, kind: "normal"), PlanProgramWeek(index: 2, kind: "deload")]
        let program = PlanProgram(
            id: UUID(), name: "PPL", weeks: 4, routineIDs: [routineID, routineID], programWeeks: weeks
        )
        return PlanDocument(
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000), appVersion: "1.0 (1)",
            exercises: [custom], routines: [routine], program: program
        )
    }

    @Test("round trip preserves every field")
    func roundTrip() throws {
        let document = sampleDocument()
        let data = try PlanCodec.encode(document)
        let decoded = try PlanCodec.decode(data)

        #expect(decoded.formatVersion == PlanDocument.currentFormatVersion)
        #expect(decoded.exercises.first?.name == "Zercher Squat")
        #expect(decoded.exercises.first?.instructions == "Cradle the bar in your elbows.")
        #expect(decoded.routines.first?.name == "Legs")
        #expect(decoded.routines.first?.ruleJSON == document.routines.first?.ruleJSON)
        #expect(decoded.routines.first?.exercises.count == 2)
        #expect(decoded.routines.first?.exercises.first?.exerciseSeedID == "bench-press")
        #expect(decoded.routines.first?.exercises.last?.supersetGroup == 1)
        #expect(decoded.program?.name == "PPL")
        #expect(decoded.program?.routineIDs == document.program?.routineIDs)
        #expect(decoded.program?.programWeeks.count == 2)
    }

    @Test("unknown future fields are ignored")
    func unknownFieldsIgnored() throws {
        let document = sampleDocument()
        let data = try PlanCodec.encode(document)
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["fromTheFuture"] = "some field a later app version added"
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)
        let decoded = try PlanCodec.decode(mutated)
        #expect(decoded.appVersion == document.appVersion)
    }

    @Test("a file needing a newer reader than this build throws a typed error")
    func formatVersionMismatch() throws {
        let document = sampleDocument()
        let data = try PlanCodec.encode(document)
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["formatVersion"] = PlanDocument.currentFormatVersion + 1
        json?["minimumReaderVersion"] = PlanDocument.currentFormatVersion + 1
        let mutated = try JSONSerialization.data(withJSONObject: json as Any)

        #expect(throws: PlanCodec.CodecError.unsupportedFormatVersion(
            found: PlanDocument.currentFormatVersion + 1, supported: PlanDocument.currentFormatVersion
        )) {
            try PlanCodec.decode(mutated)
        }
    }

    @Test("a newer file without a minimumReaderVersion stamp is rejected; with a readable one it decodes")
    func minimumReaderVersion() throws {
        let data = try PlanCodec.encode(sampleDocument())
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        json?["formatVersion"] = PlanDocument.currentFormatVersion + 1
        json?.removeValue(forKey: "minimumReaderVersion")
        let unstamped = try JSONSerialization.data(withJSONObject: json as Any)
        #expect(throws: PlanCodec.CodecError.self) { try PlanCodec.decode(unstamped) }

        json?["minimumReaderVersion"] = PlanDocument.currentFormatVersion
        let readable = try JSONSerialization.data(withJSONObject: json as Any)
        let decoded = try PlanCodec.decode(readable)
        #expect(decoded.formatVersion == PlanDocument.currentFormatVersion + 1)
        #expect(decoded.routines.count == sampleDocument().routines.count)
    }

    @Test("corrupted JSON throws a decoding error")
    func corruptedJSON() throws {
        let garbage = Data("not json at all {{{".utf8)
        #expect(throws: PlanCodec.CodecError.self) {
            try PlanCodec.decode(garbage)
        }
    }
}
