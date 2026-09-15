import Foundation
import Testing
@testable import GymCore

/// Bounds, style coherence and history context the validator applies beyond plate rounding.
@Suite("LogCommandValidator: bounds and context")
struct LogCommandValidatorBoundsTests {
    private static let benchID = UUID()
    private static let treadmillID = UUID()
    private static let plankID = UUID()
    private static let assistedDipID = UUID()

    private static func context(lastCompleted: Bool = true) -> ParseContext {
        var ctx = ParseContext(
            unit: .kg,
            onDeck: ParseContext.OnDeckSet(exerciseID: benchID, name: "Bench", loggingStyle: .weightReps),
            lastCompleted: lastCompleted
                ? ParseContext.CompletedSetRef(exerciseID: benchID, setID: UUID(), weightKg: 100, reps: 8)
                : nil
        )
        ctx.library = [
            ParseContext.ExerciseCandidate(
                id: treadmillID, name: "Running Treadmill", equipment: "machine", loggingStyle: .cardio,
                grid: .free
            ),
            ParseContext.ExerciseCandidate(
                id: plankID, name: "Plank", equipment: "bodyweight", loggingStyle: .timedHold, grid: .free
            ),
            ParseContext.ExerciseCandidate(
                id: assistedDipID, name: "Assisted Dip", equipment: "machine", loggingStyle: .assisted,
                grid: .step(5)
            )
        ]
        return ctx
    }

    private func logSet(_ values: LogSetSpec.SetValues, exercise: ExerciseRef? = nil) -> LogCommand {
        .logSet(LogSetSpec(exercise: exercise, sets: [values]))
    }

    private func failure(_ result: Result<[ValidatedCommand], ValidationError>) -> ValidationError? {
        guard case .failure(let error) = result else { return nil }
        return error
    }

    private func firstSet(_ result: Result<[ValidatedCommand], ValidationError>) -> LogSetSpec.SetValues? {
        guard case .success(let validated) = result,
              case .logSet(let spec) = validated.first?.command else { return nil }
        return spec.sets.first
    }

    @Test("rating the last set with no set completed yet is refused")
    func rateLastSetNeedsHistory() {
        let result = LogCommandValidator.validate(
            [.rateLastSet(Effort(rpe: 8))], in: Self.context(lastCompleted: false)
        )
        #expect(failure(result) == .nothingToRepeat)
        let accepted = LogCommandValidator.validate([.rateLastSet(Effort(rpe: 8))], in: Self.context())
        #expect(failure(accepted) == nil)
    }

    @Test("correcting the last set with no set completed yet is refused")
    func correctLastSetNeedsHistory() {
        let overrides = LogSetSpec.Overrides(reps: 6)
        let result = LogCommandValidator.validate(
            [.correctLastSet(overrides)], in: Self.context(lastCompleted: false)
        )
        #expect(failure(result) == .nothingToRepeat)
        let accepted = LogCommandValidator.validate([.correctLastSet(overrides)], in: Self.context())
        guard case .success(let validated) = accepted else { Issue.record("expected success"); return }
        #expect(validated.first?.command == .correctLastSet(overrides))
    }

    @Test("a hold longer than an hour is refused; a run of the same length is not")
    func durationBoundDependsOnStyle() {
        let hold = logSet(.init(durationSeconds: 3_601), exercise: .id(Self.plankID))
        #expect(failure(LogCommandValidator.validate([hold], in: Self.context())) == .durationOutOfBounds)
        let run = logSet(.init(durationSeconds: 3_601), exercise: .id(Self.treadmillID))
        #expect(failure(LogCommandValidator.validate([run], in: Self.context())) == nil)
        let dayLongRun = logSet(.init(durationSeconds: 24 * 3_600 + 1), exercise: .id(Self.treadmillID))
        let overADay = LogCommandValidator.validate([dayLongRun], in: Self.context())
        #expect(failure(overADay) == .durationOutOfBounds)
    }

    @Test("a distance over 500 km or under a metre is refused")
    func distanceBounds() {
        let tooFar = logSet(.init(distanceMeters: 500_001), exercise: .id(Self.treadmillID))
        #expect(failure(LogCommandValidator.validate([tooFar], in: Self.context())) == .distanceOutOfBounds)
        let zero = logSet(.init(distanceMeters: 0), exercise: .id(Self.treadmillID))
        #expect(failure(LogCommandValidator.validate([zero], in: Self.context())) == .distanceOutOfBounds)
        let fiveK = logSet(.init(distanceMeters: 5_000), exercise: .id(Self.treadmillID))
        #expect(firstSet(LogCommandValidator.validate([fiveK], in: Self.context()))?.distanceMeters == 5_000)
    }

    @Test("a cardio set with neither time nor distance is refused")
    func cardioNeedsTimeOrDistance() {
        let repsOnly = logSet(.init(reps: 8, weightKg: 60), exercise: .id(Self.treadmillID))
        let result = LogCommandValidator.validate([repsOnly], in: Self.context())
        #expect(failure(result) == .trackingStyleMismatch)
    }

    @Test("a cardio set drops any reps and load it was spoken with")
    func cardioStripsRepsAndLoad() {
        let values = LogSetSpec.SetValues(reps: 8, weightKg: 60, durationSeconds: 600)
        let mixed = logSet(values, exercise: .id(Self.treadmillID))
        let set = firstSet(LogCommandValidator.validate([mixed], in: Self.context()))
        #expect(set?.durationSeconds == 600)
        #expect(set?.reps == nil)
        #expect(set?.weightKg == nil)
    }

    @Test("an assisted exercise without an assistance amount is refused")
    func assistedNeedsAssistance() {
        let bare = logSet(.init(reps: 8), exercise: .id(Self.assistedDipID))
        #expect(failure(LogCommandValidator.validate([bare], in: Self.context())) == .trackingStyleMismatch)
        let assisted = logSet(.init(reps: 8, assistanceKg: 20), exercise: .id(Self.assistedDipID))
        #expect(firstSet(LogCommandValidator.validate([assisted], in: Self.context()))?.assistanceKg == 20)
    }

    @Test("more than 10 sets or zero sets in one command is refused")
    func setsCountBounds() {
        let eleven = LogCommand.logSet(LogSetSpec(
            exercise: nil, sets: Array(repeating: .init(reps: 8, weightKg: 100), count: 11)
        ))
        #expect(failure(LogCommandValidator.validate([eleven], in: Self.context())) == .setsCountOutOfBounds)
        let none = LogCommand.logSet(LogSetSpec(exercise: nil, sets: []))
        #expect(failure(LogCommandValidator.validate([none], in: Self.context())) == .setsCountOutOfBounds)
    }

    @Test("reps over 100 and weight over 600 kg are refused outright")
    func repsAndWeightUpperBounds() {
        let reps = logSet(.init(reps: 101, weightKg: 100))
        #expect(failure(LogCommandValidator.validate([reps], in: Self.context())) == .repsOutOfBounds)
        let weight = logSet(.init(reps: 5, weightKg: 600.5))
        #expect(failure(LogCommandValidator.validate([weight], in: Self.context())) == .weightOutOfBounds)
    }

    @Test("reps more than double the last set on the same exercise are suspicious, not refused")
    func repsJumpNeedsConfirmation() {
        let jump = logSet(.init(reps: 17, weightKg: 100))
        let result = LogCommandValidator.validate([jump], in: Self.context())
        guard case .success(let validated) = result, let first = validated.first else {
            Issue.record("expected success, got \(result)"); return
        }
        #expect(first.flags.contains(.needsConfirmation))
        #expect(first.flags.contains(.suspicious(reason: "reps jumped from 8 to 17")))
        let exactlyDouble = logSet(.init(reps: 16, weightKg: 100))
        let doubled = LogCommandValidator.validate([exactlyDouble], in: Self.context())
        guard case .success(let exact) = doubled else { Issue.record("expected success"); return }
        #expect(exact.first?.flags.contains(.needsConfirmation) == false)
    }

    @Test("a confidently spoken exercise validates against that exercise's own style")
    func spokenRefResolvesToCandidate() {
        let spoken = ExerciseRef.spoken("treadmill", candidates: [
            ExerciseMatch(id: Self.treadmillID, name: "Running Treadmill", score: 1)
        ])
        let repsOnly = logSet(.init(reps: 8), exercise: spoken)
        let mismatch = LogCommandValidator.validate([repsOnly], in: Self.context())
        #expect(failure(mismatch) == .trackingStyleMismatch)
        let run = logSet(.init(durationSeconds: 1_200), exercise: spoken)
        #expect(firstSet(LogCommandValidator.validate([run], in: Self.context()))?.durationSeconds == 1_200)
    }

    @Test("a spoken exercise with no candidates at all needs disambiguation")
    func spokenRefWithoutCandidates() {
        let spoken = ExerciseRef.spoken("mystery machine", candidates: [])
        let command = logSet(.init(reps: 8), exercise: spoken)
        let result = LogCommandValidator.validate([command], in: Self.context())
        #expect(failure(result) == .needsDisambiguation(candidates: []))
    }

    @Test("a note on an unresolved exercise is gated like any other spoken reference")
    func noteOnSpokenExercise() {
        let spoken = ExerciseRef.spoken("curls", candidates: [
            ExerciseMatch(id: UUID(), name: "Barbell Curl", score: 0.5),
            ExerciseMatch(id: UUID(), name: "Dumbbell Curl", score: 0.5)
        ])
        let note = LogCommand.addNote(exercise: spoken, text: "felt heavy")
        let result = LogCommandValidator.validate([note], in: Self.context())
        guard case .failure(.needsDisambiguation) = result else {
            Issue.record("expected .needsDisambiguation, got \(result)"); return
        }
    }

    @Test("the first failing command aborts the batch; earlier ones are not returned")
    func batchStopsAtFirstFailure() {
        let commands: [LogCommand] = [
            logSet(.init(reps: 8, weightKg: 100)), logSet(.init(reps: 0, weightKg: 100)), .rest(.skip)
        ]
        #expect(failure(LogCommandValidator.validate(commands, in: Self.context())) == .repsOutOfBounds)
    }
}
