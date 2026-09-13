import Foundation

/// A command the validator accepted, plus any flags the UI should surface
/// ("→ 102.5 kg", a suspicious-jump confirm, etc.).
public struct ValidatedCommand: Sendable, Equatable {
    public var command: LogCommand
    public var flags: [ValidationFlag]

    public init(command: LogCommand, flags: [ValidationFlag] = []) {
        self.command = command
        self.flags = flags
    }
}

/// A non-fatal note attached to an otherwise-accepted command.
public enum ValidationFlag: Sendable, Equatable {
    case roundedToPlates(from: Double, to: Double)
    case suspicious(reason: String)
    case needsConfirmation
}

/// A hard rejection — the command never reaches the session.
public enum ValidationError: Error, Sendable, Equatable {
    case repsOutOfBounds
    case weightOutOfBounds
    case durationOutOfBounds
    case effortOutOfBounds
    case setsCountOutOfBounds
    case implausibleWeight
    case trackingStyleMismatch
    case needsDisambiguation(candidates: [ExerciseMatch])
    case nothingToRepeat
    case nothingToUndo
    case missingOnDeck
}

/// Gates every mutation `VoiceCommandParser` proposes: bounds, unit
/// conversion, plate-grid rounding, tracking-style coherence, plausibility
/// against history, exercise resolution, and undo/repeat context (§3.5).
public enum LogCommandValidator {
    /// `hasUndoReceipt` stands in for "is there a `LogCommandReceipt` to revert" —
    /// the receipt stack itself lives in the app layer, not `GymCore`.
    public static func validate(
        _ commands: [LogCommand],
        in context: ParseContext,
        hasUndoReceipt: Bool = false
    ) -> Result<[ValidatedCommand], ValidationError> {
        var validated: [ValidatedCommand] = []
        for command in commands {
            switch validate(one: command, in: context, hasUndoReceipt: hasUndoReceipt) {
            case .success(let value): validated.append(value)
            case .failure(let error): return .failure(error)
            }
        }
        return .success(validated)
    }

    private static func validate(
        one command: LogCommand, in context: ParseContext, hasUndoReceipt: Bool
    ) -> Result<ValidatedCommand, ValidationError> {
        switch command {
        case .logSet(let spec):
            return validateLogSet(spec, in: context)
        case .repeatPrevious(let overrides):
            return validateRepeatPrevious(overrides, context: context)
        case .rateLastSet(let effort):
            return validateRateLastSet(effort, context: context)
        case .correctLastSet(let overrides):
            return validateCorrectLastSet(overrides, context: context)
        case .undo:
            return validateUndo(hasReceipt: hasUndoReceipt)
        case .swapExercise, .addExercise, .removeExercise, .rest, .addNote, .query, .completeOnDeck:
            return .success(ValidatedCommand(command: command))
        }
    }

    private static func validateRepeatPrevious(
        _ overrides: LogSetSpec.Overrides, context: ParseContext
    ) -> Result<ValidatedCommand, ValidationError> {
        guard context.lastCompleted != nil else { return .failure(.nothingToRepeat) }
        return .success(ValidatedCommand(command: .repeatPrevious(overrides: overrides)))
    }

    private static func validateRateLastSet(
        _ effort: Effort, context: ParseContext
    ) -> Result<ValidatedCommand, ValidationError> {
        guard context.lastCompleted != nil else { return .failure(.nothingToRepeat) }
        guard (5...10).contains(effort.rpe) else { return .failure(.effortOutOfBounds) }
        return .success(ValidatedCommand(command: .rateLastSet(effort)))
    }

    private static func validateCorrectLastSet(
        _ overrides: LogSetSpec.Overrides, context: ParseContext
    ) -> Result<ValidatedCommand, ValidationError> {
        guard context.lastCompleted != nil else { return .failure(.nothingToRepeat) }
        return .success(ValidatedCommand(command: .correctLastSet(overrides)))
    }

    private static func validateUndo(
        hasReceipt: Bool
    ) -> Result<ValidatedCommand, ValidationError> {
        guard hasReceipt else { return .failure(.nothingToUndo) }
        return .success(ValidatedCommand(command: .undo))
    }

    private static func validateLogSet(
        _ spec: LogSetSpec, in context: ParseContext
    ) -> Result<ValidatedCommand, ValidationError> {
        if spec.exercise == nil, context.onDeck == nil { return .failure(.missingOnDeck) }
        if case .spoken(_, let candidates) = spec.exercise {
            let best = candidates.first?.score ?? 0
            let runnerUp = candidates.count > 1 ? candidates[1].score : 0
            if best < ExerciseMatcher.threshold || (best - runnerUp) < ExerciseMatcher.margin {
                return .failure(.needsDisambiguation(candidates: candidates))
            }
        }
        guard (1...10).contains(spec.sets.count) else { return .failure(.setsCountOutOfBounds) }
        if let effort = spec.effort, !(5...10).contains(effort.rpe) { return .failure(.effortOutOfBounds) }

        var flags: [ValidationFlag] = []
        var roundedSets: [LogSetSpec.SetValues] = []
        for values in spec.sets {
            switch validateSetValues(values, spec: spec, context: context) {
            case .failure(let error): return .failure(error)
            case .success(let (rounded, setFlags)):
                roundedSets.append(rounded)
                flags.append(contentsOf: setFlags)
            }
        }
        var result = spec
        result.sets = roundedSets
        return .success(ValidatedCommand(command: .logSet(result), flags: flags))
    }

    private static func validateSetValues(
        _ values: LogSetSpec.SetValues, spec: LogSetSpec, context: ParseContext
    ) -> Result<(LogSetSpec.SetValues, [ValidationFlag]), ValidationError> {
        var values = values
        var flags: [ValidationFlag] = []

        if let reps = values.reps, !(1...100).contains(reps) { return .failure(.repsOutOfBounds) }
        if let duration = values.durationSeconds, !(1...3600).contains(duration) {
            return .failure(.durationOutOfBounds)
        }

        if let styleError = validateStyle(&values, context: context) {
            return .failure(styleError)
        }

        if let weightValidation = validateWeight(&values, context: context) {
            switch weightValidation {
            case .success(let weightFlags):
                flags.append(contentsOf: weightFlags)
            case .failure(let error):
                return .failure(error)
            }
        }

        if let reps = values.reps, let previousReps = context.lastCompleted?.reps, reps > previousReps * 2 {
            flags.append(.suspicious(reason: "reps jumped from \(previousReps) to \(reps)"))
            flags.append(.needsConfirmation)
        }
        return .success((values, flags))
    }

    private static func validateStyle(
        _ values: inout LogSetSpec.SetValues, context: ParseContext
    ) -> ValidationError? {
        let style = context.onDeck?.loggingStyle
        if style == .timedHold, values.durationSeconds == nil, values.reps != nil {
            return .trackingStyleMismatch
        }
        if style == .bodyweightReps { values.isBodyweight = true; values.weightKg = 0 }
        if style == .assisted, values.assistanceKg == nil {
            return .trackingStyleMismatch
        }
        return nil
    }

    private static func validateWeight(
        _ values: inout LogSetSpec.SetValues, context: ParseContext
    ) -> Result<[ValidationFlag], ValidationError>? {
        guard let weight = values.weightKg else { return nil }
        guard weight >= 0, weight <= 600 else { return .failure(.weightOutOfBounds) }

        var flags: [ValidationFlag] = []

        if weight == 0, !values.isBodyweight, values.durationSeconds == nil, values.assistanceKg == nil {
            flags.append(.needsConfirmation)
        } else if weight > 0 {
            let (rounded, roundFlag) = roundToPlateGrid(weight, context: context)
            if let roundFlag {
                if abs(rounded - weight) > max(context.onDeck?.incrementKg ?? 2.5, 2.5) {
                    return .failure(.implausibleWeight)
                }
                values.weightKg = rounded
                flags.append(roundFlag)
            }
        }

        if let previous = context.lastCompleted?.weightKg, previous > 0, weight > previous * 1.5 {
            flags.append(.suspicious(reason: "weight jumped from \(previous) to \(weight)"))
            flags.append(.needsConfirmation)
        }

        return .success(flags)
    }

    /// Rounds to the nearest loadable weight for a barred exercise, else the
    /// increment grid. Returns `nil` flag when the weight is already on-grid.
    private static func roundToPlateGrid(
        _ weight: Double, context: ParseContext
    ) -> (Double, ValidationFlag?) {
        guard let bar = context.bar else {
            let increment = context.onDeck?.incrementKg ?? 2.5
            let rounded = (weight / increment).rounded() * increment
            return (rounded, abs(rounded - weight) < 0.01 ? nil : .roundedToPlates(from: weight, to: rounded))
        }
        switch PlateCalculator.load(target: weight, bar: bar, plates: context.plateSet) {
        case .exact:
            return (weight, nil)
        case .tooLight:
            return (bar.weightKg, .roundedToPlates(from: weight, to: bar.weightKg))
        case .nearest(let below, let above):
            let candidates = [below, above].compactMap { $0 }
            guard let nearest = candidates.min(by: { abs($0.total - weight) < abs($1.total - weight) }) else {
                return (weight, nil)
            }
            return (nearest.total, .roundedToPlates(from: weight, to: nearest.total))
        }
    }
}
