import Foundation
import Testing

@testable import GymCore

/// Property-style fuzzing of the `.gymplan` boundary: `PlanCodec.decode` must never trap on a
/// mutated or byte-corrupted file, and whatever it does decode must come out of `sanitised()`
/// inside the bounds `PlanLimits` documents — on every path, for every hostile value, including
/// the ones JSON can't carry (NaN, infinities) fed straight into the value types.
@Suite("Fuzz: PlanCodec + PlanSanitizing", .serialized)
struct FuzzPlanCodecTests {
    static let iterations = 200
    static let seed: UInt64 = 0x91A4_0002
    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    static func fixture() -> PlanDocument {
        let routineA = UUID()
        let routineB = UUID()
        let set = PlanSet(
            order: 0, kind: "working", targetReps: 8, targetRepsHigh: 12, targetWeightKg: 60,
            targetRPE: 8, targetSeconds: 45, targetDistanceMeters: 500
        )
        let slot = PlanRoutineExercise(
            order: 0, exerciseSeedID: "Barbell_Squat", exerciseName: "Squat", supersetGroup: 1,
            restOverrideSeconds: 90, note: "n", ruleJSON: "{}", sets: [set]
        )
        let custom = PlanRoutineExercise(
            order: 1, exerciseName: "Zercher Squat", supersetGroup: 1, sets: [set]
        )
        return PlanDocument(
            exportedAt: date, appVersion: "1.0",
            exercises: [PlanExercise(
                id: UUID(), name: "Zercher Squat", primaryMuscles: ["quads"], equipment: "barbell",
                mechanic: "compound", barType: "olympic", instructions: "Brace.", notes: "n"
            )],
            routines: [
                PlanRoutine(
                    id: routineA, name: "Legs", notes: "n", ruleJSON: "{}", exercises: [slot, custom]
                ),
                PlanRoutine(id: routineB, name: "Push", exercises: [slot])
            ],
            program: PlanProgram(
                id: UUID(), name: "Block", weeks: 4, routineIDs: [routineA, routineB, routineA],
                programWeeks: [
                    PlanProgramWeek(index: 1, kind: "normal"), PlanProgramWeek(index: 4, kind: "deload")
                ]
            )
        )
    }

    static func tree() throws -> FuzzJSON {
        let data = try PlanCodec.encode(fixture())
        return FuzzJSON(any: try JSONSerialization.jsonObject(with: data))
    }

    static func check(_ data: Data, label: @autoclosure () -> String) -> PlanDocument? {
        do {
            return try PlanCodec.decode(data)
        } catch is PlanCodec.CodecError {
            return nil
        } catch {
            Issue.record("untyped error for \(label()): \(error)")
            return nil
        }
    }

    // MARK: - Bounds

    /// Every documented `PlanLimits`/`PlanSanitizing` bound, checked on a sanitised document.
    static func assertBounds(_ document: PlanDocument, label: @autoclosure () -> String) {
        for exercise in document.exercises {
            #expect(!exercise.name.isEmpty && exercise.name.count <= PlanLimits.maxNameLength, "\(label())")
            let increment = exercise.incrementKg
            #expect(increment > 0 && increment <= PlanLimits.maxIncrementKg, "\(label())")
            #expect((0...PlanLimits.maxRestSeconds).contains(exercise.restSeconds), "\(label())")
            #expect(exercise.instructions.count <= PlanLimits.maxInstructionsLength, "\(label())")
            #expect(exercise.notes.count <= PlanLimits.maxNotesLength, "\(label())")
        }
        for routine in document.routines {
            #expect(routine.name.count <= PlanLimits.maxNameLength, "\(label())")
            #expect(routine.notes.count <= PlanLimits.maxNotesLength, "\(label())")
            #expect((1...PlanLimits.maxRepRange).contains(routine.repRangeLow), "\(label())")
            #expect((1...PlanLimits.maxRepRange).contains(routine.repRangeHigh), "\(label())")
            #expect(routine.repRangeLow <= routine.repRangeHigh, "\(label())")
            assertSlots(routine.exercises, label: label())
        }
        if let program = document.program {
            #expect(program.name.count <= PlanLimits.maxNameLength, "\(label())")
            #expect((1...PlanLimits.maxProgramWeeks).contains(program.weeks), "\(label())")
            #expect(program.programWeeks.count == program.weeks, "\(label())")
            #expect(program.programWeeks.map(\.index) == Array(1...program.weeks), "\(label())")
            #expect(program.programWeeks.allSatisfy { ["normal", "deload", "rest"].contains($0.kind) })
            #expect(program.routineIDs.count <= PlanLimits.maxProgramDays, "\(label())")
            let known = Set(document.routines.map(\.id))
            #expect(program.routineIDs.allSatisfy(known.contains), "\(label())")
        }
    }

    private static func assertSlots(_ slots: [PlanRoutineExercise], label: String) {
        var groupCounts: [Int: Int] = [:]
        for slot in slots {
            let nameLength = slot.exerciseName.count
            #expect(nameLength > 0 && nameLength <= PlanLimits.maxNameLength, "\(label)")
            #expect(slot.note.count <= PlanLimits.maxNotesLength, "\(label)")
            if let rest = slot.restOverrideSeconds {
                #expect(rest > 0 && rest <= PlanLimits.maxRestSeconds, "\(label)")
            }
            if let group = slot.supersetGroup { groupCounts[group, default: 0] += 1 }
            for set in slot.sets {
                #expect(SetKind(rawValue: set.kind) != nil, "\(label)")
                #expect(set.targetReps.map { $0 >= 1 } ?? true, "\(label)")
                #expect(set.targetRepsHigh.map { $0 >= 1 } ?? true, "\(label)")
                if let low = set.targetReps, let high = set.targetRepsHigh {
                    #expect(low <= high, "\(label)")
                }
                #expect(set.targetWeightKg.map { $0.isFinite && $0 >= 0 } ?? true, "\(label)")
                #expect(set.targetRPE.map { $0.isFinite && $0 >= 1 && $0 <= 10 } ?? true, "\(label)")
                #expect(set.targetSeconds.map { $0 > 0 } ?? true, "\(label)")
                #expect(set.targetDistanceMeters.map { $0.isFinite && $0 > 0 } ?? true, "\(label)")
            }
        }
        #expect(groupCounts.values.allSatisfy { $0 >= 2 }, "orphan superset survived: \(label)")
    }

    // MARK: - Tests

    @Test("the fixture decodes and is already within bounds")
    func fixtureDecodes() throws {
        let document = try #require(Self.check(try PlanCodec.encode(Self.fixture()), label: "fixture"))
        Self.assertBounds(document.sanitised(), label: "fixture")
        #expect(document.sanitised().routines.count == 2)
    }

    @Test("field-by-field mutations decode-or-throw, and every decoded document sanitises into bounds")
    func fieldMutations() throws {
        let tree = try Self.tree()
        let paths = tree.paths()
        var rng = FuzzRNG(seed: Self.seed)
        for iteration in 0..<Self.iterations {
            let path = rng.pick(paths)
            let mutated = tree.replacing(path: path) { _ in
                rng.int(6) == 0 ? nil : FuzzValues.leaf(&rng, allowHuge: iteration % 50 == 3)
            }
            let label = "iteration \(iteration) path \(path)"
            guard let document = Self.check(Data(mutated.render().utf8), label: label) else { continue }
            Self.assertBounds(document.sanitised(), label: label)
        }
    }

    @Test("byte-level corruption never traps")
    func byteCorruption() throws {
        let valid = try PlanCodec.encode(Self.fixture())
        var rng = FuzzRNG(seed: Self.seed &+ 1)
        for iteration in 0..<Self.iterations {
            if let document = Self.check(FuzzBytes.corrupt(valid, &rng), label: "corruption \(iteration)") {
                Self.assertBounds(document.sanitised(), label: "corruption \(iteration)")
            }
        }
    }

    /// The values JSON can't carry but the value types can: NaN, ±inf, `-0`, `Int.min`/`Int.max`.
    /// Built directly and pushed through `sanitised()`.
    @Test("hostile numbers fed straight into the value types sanitise into bounds")
    func hostileValueTypes() {
        let doubles: [Double] = [.nan, .infinity, -.infinity, -0.0, 0, -1, 1e308, -1e308, 5e-324, 1e-300]
        let ints: [Int] = [.min, .max, -1, 0, 1, 51, 367, 3601, 1_000_000]
        var rng = FuzzRNG(seed: Self.seed &+ 2)
        for iteration in 0..<Self.iterations {
            var document = Self.fixture()
            document.exercises[0].incrementKg = rng.pick(doubles)
            document.exercises[0].restSeconds = rng.pick(ints)
            document.routines[0].repRangeLow = rng.pick(ints)
            document.routines[0].repRangeHigh = rng.pick(ints)
            document.routines[0].exercises[0].restOverrideSeconds = rng.bool() ? rng.pick(ints) : nil
            document.routines[0].exercises[0].supersetGroup = rng.bool() ? rng.pick(ints) : nil
            var set = document.routines[0].exercises[0].sets[0]
            set.targetReps = rng.bool() ? rng.pick(ints) : nil
            set.targetRepsHigh = rng.bool() ? rng.pick(ints) : nil
            set.targetWeightKg = rng.bool() ? rng.pick(doubles) : nil
            set.targetRPE = rng.bool() ? rng.pick(doubles) : nil
            set.targetSeconds = rng.bool() ? rng.pick(ints) : nil
            set.targetDistanceMeters = rng.bool() ? rng.pick(doubles) : nil
            set.kind = rng.pick(["working", "warmup", "", "sprint", "\u{0}"])
            document.routines[0].exercises[0].sets = [set]
            document.program?.weeks = rng.pick(ints)
            document.program?.routineIDs = Array(repeating: document.routines[0].id, count: rng.int(400))
                + [UUID()]
            document.program?.programWeeks = (0..<rng.int(60)).map {
                PlanProgramWeek(index: rng.pick(ints + [$0]), kind: rng.pick(["normal", "rest", "x", ""]))
            }
            if rng.int(10) == 0 { document.exercises[0].name = rng.pick(["", " ", "\u{0}\u{1}", "\n"]) }
            if rng.int(10) == 0 { document.routines[0].exercises[1].exerciseName = "" }
            Self.assertBounds(document.sanitised(), label: "value types \(iteration)")
        }
    }

    @Test("a 10 MB name/notes/instructions is clamped to the documented lengths")
    func hugeText() {
        var document = Self.fixture()
        let huge = String(repeating: "q", count: FuzzValues.hugeStringLength)
        document.exercises[0].name = huge
        document.exercises[0].instructions = huge
        document.routines[0].notes = huge
        document.program?.name = huge
        let sanitised = document.sanitised()
        #expect(sanitised.exercises[0].name.count == PlanLimits.maxNameLength)
        #expect(sanitised.exercises[0].instructions.count == PlanLimits.maxInstructionsLength)
        #expect(sanitised.routines[0].notes.count == PlanLimits.maxNotesLength)
        #expect(sanitised.program?.name.count == PlanLimits.maxNameLength)
    }
}
