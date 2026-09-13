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
                exerciseID: benchID, name: "Barbell Bench Press - Medium Grip", loggingStyle: .weightReps
            ),
            lastCompleted: ParseContext.CompletedSetRef(
                exerciseID: benchID, setID: UUID(), weightKg: lastWeightKg, reps: lastReps
            ),
            bar: .olympic,
            plateSet: PlateStock.standardKg
        )
    }

    private static let lateralRaiseID = UUID()
    private static let cableRowID = UUID()
    private static let pullUpsID = UUID()

    /// Bench on deck; a dumbbell, a cable and a bodyweight exercise in the library.
    private static func accessoryContext() -> ParseContext {
        var ctx = context()
        ctx.library = [
            ParseContext.ExerciseCandidate(
                id: lateralRaiseID, name: "Side Lateral Raise", equipment: "dumbbell",
                loggingStyle: .weightReps, grid: .step(2)
            ),
            ParseContext.ExerciseCandidate(
                id: cableRowID, name: "Seated Cable Row", equipment: "cable",
                loggingStyle: .weightReps, grid: .step(5)
            ),
            ParseContext.ExerciseCandidate(
                id: pullUpsID, name: "Pullups", equipment: "bodyweight", loggingStyle: .bodyweightReps,
                grid: .free
            )
        ]
        return ctx
    }

    private func logSet(_ values: LogSetSpec.SetValues, exercise: ExerciseRef? = nil) -> LogCommand {
        .logSet(LogSetSpec(exercise: exercise, sets: [values]))
    }

    private func accepted(_ result: Result<[ValidatedCommand], ValidationError>) -> ValidatedCommand? {
        guard case .success(let validated) = result else { return nil }
        return validated.first
    }

    private func weight(_ validated: ValidatedCommand?) -> Double? {
        guard case .logSet(let spec) = validated?.command else { return nil }
        return spec.sets.first?.weightKg
    }

    @Test(
        "5–15 kg on a dumbbell exercise is accepted on its own grid",
        arguments: [5.0, 7.5, 10, 12, 14, 15]
    )
    func lightDumbbellWeights(kg: Double) {
        let command = logSet(.init(reps: 12, weightKg: kg), exercise: .id(Self.lateralRaiseID))
        let result = LogCommandValidator.validate([command], in: Self.accessoryContext())
        let first = accepted(result)
        #expect(first != nil, "\(kg) kg: \(result)")
        let expected = (kg / 2).rounded() * 2
        #expect(weight(first) == expected)
        #expect(first?.flags.contains(.needsConfirmation) == false)
    }

    @Test("a cable stack rounds to its own step, never up to a bar")
    func cableStack() {
        let command = logSet(.init(reps: 10, weightKg: 12), exercise: .id(Self.cableRowID))
        let first = accepted(LogCommandValidator.validate([command], in: Self.accessoryContext()))
        #expect(weight(first) == 10)
        #expect(first?.flags == [.roundedToPlates(from: 12, to: 10)])
    }

    @Test("unknown equipment with a gym bar: under the bar steps by the smallest plate pair")
    func lightWeightUnknownEquipment() {
        let command = logSet(.init(reps: 8, weightKg: 12))
        let first = accepted(LogCommandValidator.validate([command], in: Self.context()))
        #expect(weight(first) == 12.5)
    }

    @Test("a known barbell exercise refuses a weight lighter than the bar")
    func lightWeightOnBar() {
        var ctx = Self.context()
        ctx.onDeck?.grid = .plates(bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
        let result = LogCommandValidator.validate([logSet(.init(reps: 8, weightKg: 12))], in: ctx)
        switch result {
        case .failure(.implausibleWeight): break
        default: Issue.record("expected .implausibleWeight, got \(result)")
        }
    }

    @Test("no bar in the context means no plate rounding at all")
    func noBarNoPlates() {
        let ctx = ParseContext(
            unit: .kg,
            onDeck: ParseContext.OnDeckSet(exerciseID: Self.benchID, name: "Curl", loggingStyle: .weightReps)
        )
        let first = accepted(LogCommandValidator.validate([logSet(.init(reps: 12, weightKg: 10))], in: ctx))
        #expect(weight(first) == 10)
        #expect(first?.flags.isEmpty == true)
    }

    @Test("a named exercise keeps its own tracking style, not the on-deck one")
    func namedExerciseStyle() {
        var ctx = Self.accessoryContext()
        ctx.onDeck = ParseContext.OnDeckSet(
            exerciseID: Self.pullUpsID, name: "Pullups", loggingStyle: .bodyweightReps
        )
        let command = logSet(.init(reps: 8, weightKg: 100), exercise: .id(Self.benchID))
        let first = accepted(LogCommandValidator.validate([command], in: ctx))
        #expect(weight(first) == 100)
        if case .logSet(let spec) = first?.command { #expect(spec.sets.first?.isBodyweight == false) }
        let pullUps = logSet(.init(reps: 8, weightKg: 100), exercise: .id(Self.pullUpsID))
        if case .logSet(let spec) = accepted(LogCommandValidator.validate([pullUps], in: ctx))?.command {
            #expect(spec.sets.first?.isBodyweight == true)
            #expect(spec.sets.first?.weightKg == 0)
        } else {
            Issue.record("expected the bodyweight rewrite")
        }
    }

    @Test("history only flags a jump on the same exercise")
    func plausibilityPerExercise() {
        let other = logSet(.init(reps: 12, weightKg: 200), exercise: .id(Self.cableRowID))
        let first = accepted(LogCommandValidator.validate([other], in: Self.accessoryContext()))
        #expect(first?.flags.contains(.needsConfirmation) == false)
        let same = logSet(.init(reps: 8, weightKg: 200))
        let flagged = accepted(LogCommandValidator.validate([same], in: Self.accessoryContext()))
        #expect(flagged?.flags.contains(.needsConfirmation) == true)
    }

    @Test("an unresolved exercise is refused for add/swap/remove/query too")
    func spokenRefsGated() {
        let spoken = ExerciseRef.spoken("easy bar curls", candidates: [
            ExerciseMatch(id: UUID(), name: "Barbell Curl", score: 0.5)
        ])
        for command in [
            LogCommand.addExercise(spoken), .removeExercise(spoken),
            .swapExercise(target: .onDeck, replacement: spoken), .query(.personalRecord(spoken))
        ] {
            let result = LogCommandValidator.validate([command], in: Self.context())
            guard case .failure(.needsDisambiguation) = result else {
                Issue.record("expected .needsDisambiguation for \(command), got \(result)"); return
            }
        }
        let ok = LogCommandValidator.validate([.addExercise(.id(Self.cableRowID))], in: Self.context())
        #expect(accepted(ok) != nil)
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
