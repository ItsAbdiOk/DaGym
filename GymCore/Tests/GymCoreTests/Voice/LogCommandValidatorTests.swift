import Foundation
import Testing
@testable import GymCore

@Suite("LogCommandValidator")
struct LogCommandValidatorTests {
    private static let benchID = UUID()

    private static func context(lastWeightKg: Double? = 100, lastReps: Int? = 8) -> ParseContext {
        ParseContext(
            unit: .kg,
            onDeck: ParseContext.OnDeckSet(
                exerciseID: benchID, name: "Barbell Bench Press", loggingStyle: .weightReps,
                prefilledWeightKg: 100, prefilledReps: 8
            ),
            lastCompleted: ParseContext.CompletedSetRef(
                exerciseID: benchID, setID: UUID(), weightKg: lastWeightKg, reps: lastReps
            ),
            bar: .olympic,
            plateSet: PlateStock.standardKg
        )
    }

    private func logSet(_ values: LogSetSpec.SetValues) -> LogCommand {
        .logSet(LogSetSpec(sets: [values]))
    }

    @Test("225 lb rounds to the nearest loadable plate weight and is flagged")
    func lbToKgPlateRounding() {
        let weightKg = WeightUnit.lb.toKg(225)
        let command = logSet(.init(reps: 5, weightKg: weightKg))
        let result = LogCommandValidator.validate([command], in: Self.context())
        guard case .success(let validated) = result, let first = validated.first else {
            Issue.record("expected success"); return
        }
        guard case .logSet(let spec) = first.command, let rounded = spec.sets.first?.weightKg else {
            Issue.record("expected logSet"); return
        }
        #expect(abs(rounded - 102.5) < 0.01)
        #expect(first.flags.contains { if case .roundedToPlates = $0 { return true } else { return false } })
    }

    @Test("reps of 0 is rejected")
    func repsZeroRejected() {
        let command = logSet(.init(reps: 0, weightKg: 100))
        let result = LogCommandValidator.validate([command], in: Self.context())
        switch result {
        case .failure(.repsOutOfBounds): break
        default: Issue.record("expected .repsOutOfBounds, got \(result)")
        }
    }

    @Test("weight 0 on a weightReps exercise needs confirmation, not rejection")
    func weightZeroNeedsConfirmation() {
        let command = logSet(.init(reps: 8, weightKg: 0))
        let result = LogCommandValidator.validate([command], in: Self.context())
        guard case .success(let validated) = result, let first = validated.first else {
            Issue.record("expected success, got \(result)"); return
        }
        #expect(first.flags.contains(.needsConfirmation))
    }

    @Test("a timed exercise given reps but no duration is rejected")
    func timedWithRepsOnlyRejected() {
        let plankID = UUID()
        let ctx = ParseContext(
            unit: .kg,
            onDeck: ParseContext.OnDeckSet(exerciseID: plankID, name: "Plank", loggingStyle: .timedHold)
        )
        let command = logSet(.init(reps: 10))
        let result = LogCommandValidator.validate([command], in: ctx)
        switch result {
        case .failure(.trackingStyleMismatch): break
        default: Issue.record("expected .trackingStyleMismatch, got \(result)")
        }
    }

    @Test("a 1.6x weight jump over history is suspicious, not rejected")
    func suspiciousJumpNeedsConfirmation() {
        let command = logSet(.init(reps: 8, weightKg: 160)) // 1.6x the last completed 100 kg
        let result = LogCommandValidator.validate([command], in: Self.context())
        guard case .success(let validated) = result, let first = validated.first else {
            Issue.record("expected success, got \(result)"); return
        }
        #expect(first.flags.contains(.needsConfirmation))
        #expect(first.flags.contains { if case .suspicious = $0 { return true } else { return false } })
    }

    @Test("repeatPrevious with nothing completed yet fails with .nothingToRepeat")
    func nothingToRepeat() {
        let ctx = ParseContext(unit: .kg, onDeck: nil, lastCompleted: nil)
        let result = LogCommandValidator.validate([.repeatPrevious(overrides: .init())], in: ctx)
        switch result {
        case .failure(.nothingToRepeat): break
        default: Issue.record("expected .nothingToRepeat, got \(result)")
        }
    }

    @Test("undo with an empty receipt stack fails with .nothingToUndo")
    func nothingToUndo() {
        let result = LogCommandValidator.validate([.undo], in: Self.context(), hasUndoReceipt: false)
        switch result {
        case .failure(.nothingToUndo): break
        default: Issue.record("expected .nothingToUndo, got \(result)")
        }
    }

    @Test("undo succeeds when a receipt is on the stack")
    func undoWithReceipt() {
        let result = LogCommandValidator.validate([.undo], in: Self.context(), hasUndoReceipt: true)
        switch result {
        case .success: break
        default: Issue.record("expected success, got \(result)")
        }
    }
}
