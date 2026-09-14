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
    case distanceOutOfBounds
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
        case .swapExercise(let target, let replacement):
            return resolved(target).flatMap { _ in resolved(replacement) }.map { _ in
                ValidatedCommand(command: command)
            }
        case .addExercise(let exercise), .removeExercise(let exercise):
            return resolved(exercise).map { _ in ValidatedCommand(command: command) }
        case .addNote(let exercise, _):
            return resolved(exercise).map { _ in ValidatedCommand(command: command) }
        case .query(.lastSession(let exercise)), .query(.personalRecord(let exercise)):
            return resolved(exercise).map { _ in ValidatedCommand(command: command) }
        case .rest, .completeOnDeck:
            return .success(ValidatedCommand(command: command))
        }
    }

    /// `.spoken` passes only when its best candidate would have auto-resolved;
    /// otherwise the app shows chips, whatever the command.
    private static func resolved(_ exercise: ExerciseRef?) -> Result<Void, ValidationError> {
        guard case .spoken(_, let candidates) = exercise else { return .success(()) }
        let best = candidates.first?.score ?? 0
        let runnerUp = candidates.count > 1 ? candidates[1].score : 0
        guard ExerciseMatcher.isConfident(best: best, runnerUp: runnerUp) else {
            return .failure(.needsDisambiguation(candidates: candidates))
        }
        return .success(())
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

    // MARK: - logSet

    /// The exercise a spec lands on, with what the validator needs to know about it.
    private struct Target {
        var exerciseID: UUID
        var loggingStyle: ParseContext.LoggingStyle?
        var grid: LoadGrid
        var incrementKg: Double
    }

    private static func target(
        for spec: LogSetSpec, in context: ParseContext
    ) -> Result<Target, ValidationError> {
        let fallbackGrid: LoadGrid = context.bar.map {
            .unknown(bar: $0, plates: context.plateSet, collarsKg: 0)
        } ?? .step(TrainingConstants.defaultStepKg)

        func named(_ id: UUID) -> Target {
            let candidate = (context.sessionExercises + context.library).first { $0.id == id }
            let grid = candidate?.grid ?? fallbackGrid
            return Target(
                exerciseID: id, loggingStyle: candidate?.loggingStyle, grid: grid,
                incrementKg: gridStep(grid)
            )
        }

        switch spec.exercise {
        case .none, .onDeck:
            guard let onDeck = context.onDeck else { return .failure(.missingOnDeck) }
            let grid = onDeck.grid ?? context.bar.map {
                .unknown(bar: $0, plates: context.plateSet, collarsKg: 0)
            } ?? .step(onDeck.incrementKg)
            return .success(Target(
                exerciseID: onDeck.exerciseID, loggingStyle: onDeck.loggingStyle, grid: grid,
                incrementKg: onDeck.incrementKg
            ))
        case .id(let id):
            return .success(named(id))
        case .spoken(_, let candidates):
            return resolved(spec.exercise).flatMap {
                guard let best = candidates.first else {
                    return .failure(.needsDisambiguation(candidates: candidates))
                }
                return .success(named(best.id))
            }
        }
    }

    private static func gridStep(_ grid: LoadGrid) -> Double {
        if case .step(let step) = grid, step > 0 { return step }
        return TrainingConstants.defaultStepKg
    }

    private static func validateLogSet(
        _ spec: LogSetSpec, in context: ParseContext
    ) -> Result<ValidatedCommand, ValidationError> {
        let target: Target
        switch self.target(for: spec, in: context) {
        case .failure(let error): return .failure(error)
        case .success(let value): target = value
        }
        guard (1...10).contains(spec.sets.count) else { return .failure(.setsCountOutOfBounds) }

        var flags: [ValidationFlag] = []
        var roundedSets: [LogSetSpec.SetValues] = []
        for values in spec.sets {
            switch validateSetValues(values, target: target, context: context) {
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
        _ values: LogSetSpec.SetValues, target: Target, context: ParseContext
    ) -> Result<(LogSetSpec.SetValues, [ValidationFlag]), ValidationError> {
        var values = values
        var flags: [ValidationFlag] = []

        if let reps = values.reps, !(1...100).contains(reps) { return .failure(.repsOutOfBounds) }
        // A plank tops out at an hour; a run does not.
        let longest = target.loggingStyle == .cardio ? 24 * 3600 : 3600
        if let duration = values.durationSeconds, !(1...longest).contains(duration) {
            return .failure(.durationOutOfBounds)
        }
        if let meters = values.distanceMeters, !(1...500_000).contains(meters) {
            return .failure(.distanceOutOfBounds)
        }

        if let styleError = validateStyle(&values, style: target.loggingStyle) {
            return .failure(styleError)
        }

        // History only says something about the same exercise (§3.5 "previous best for this exercise").
        let previous = context.lastCompleted.flatMap { $0.exerciseID == target.exerciseID ? $0 : nil }

        if let weightValidation = validateWeight(&values, target: target, previous: previous) {
            switch weightValidation {
            case .success(let weightFlags):
                flags.append(contentsOf: weightFlags)
            case .failure(let error):
                return .failure(error)
            }
        }

        if let reps = values.reps, let previousReps = previous?.reps, reps > previousReps * 2 {
            flags.append(.suspicious(reason: "reps jumped from \(previousReps) to \(reps)"))
            flags.append(.needsConfirmation)
        }
        return .success((values, flags))
    }

    private static func validateStyle(
        _ values: inout LogSetSpec.SetValues, style: ParseContext.LoggingStyle?
    ) -> ValidationError? {
        if style == .timedHold, values.durationSeconds == nil, values.reps != nil {
            return .trackingStyleMismatch
        }
        if style == .cardio {
            // "Eight at sixty" on a treadmill row is not a run: a cardio set needs a time or a
            // distance, and never carries reps or load.
            guard values.durationSeconds != nil || values.distanceMeters != nil else {
                return .trackingStyleMismatch
            }
            values.reps = nil
            values.weightKg = nil
        }
        if style == .bodyweightReps { values.isBodyweight = true; values.weightKg = 0 }
        if style == .assisted, values.assistanceKg == nil {
            return .trackingStyleMismatch
        }
        return nil
    }

    private static func validateWeight(
        _ values: inout LogSetSpec.SetValues, target: Target, previous: ParseContext.CompletedSetRef?
    ) -> Result<[ValidationFlag], ValidationError>? {
        guard let weight = values.weightKg else { return nil }
        guard weight >= 0, weight <= 600 else { return .failure(.weightOutOfBounds) }

        var flags: [ValidationFlag] = []

        if weight == 0, !values.isBodyweight, values.durationSeconds == nil, values.assistanceKg == nil {
            flags.append(.needsConfirmation)
        } else if weight > 0 {
            let rounded = target.grid.nearest(weight)
            if abs(rounded - weight) >= 0.01 {
                if abs(rounded - weight) > max(target.incrementKg, TrainingConstants.defaultStepKg) {
                    return .failure(.implausibleWeight)
                }
                values.weightKg = rounded
                flags.append(.roundedToPlates(from: weight, to: rounded))
            }
        }

        if let previousWeight = previous?.weightKg, previousWeight > 0, weight > previousWeight * 1.5 {
            flags.append(.suspicious(reason: "weight jumped from \(previousWeight) to \(weight)"))
            flags.append(.needsConfirmation)
        }

        return .success(flags)
    }
}
