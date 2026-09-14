import Foundation
import GymCore

/// What a spoken phrase resolved to: the on-deck (or named) exercise, and the values that would
/// go on its next set. Shown on the confirm screen (4B), committed by Log, loaded into the
/// steppers by Fix.
struct WatchVoiceParse {
    var phrase: String
    var exerciseID: UUID
    var exerciseName: String
    var setNumber: Int
    var weightKg: Double?
    var reps: Int?
    var effort: Effort?
    var durationSeconds: Int?
}

/// The watch's slice of the phone's `VoiceLogController`: the same `GymCore` parser and
/// validator over the same `ParseContext` (built the way `VoiceLogController+Context` builds
/// it), reduced to the commands a wrist can act on — log a set, repeat the last one, complete
/// the on-deck set. Everything else ("swap", "note", queries) reads as "couldn't log that".
/// Always confirmed before it commits; nothing auto-logs on the watch.
@MainActor
enum WatchVoiceLog {
    static func parse(
        _ phrase: String, session: WorkoutSession, store: WorkoutStore, unit: WeightUnit
    ) -> WatchVoiceParse? {
        let context = buildContext(session: session, store: store, unit: unit)
        let result = VoiceCommandParser.parse(phrase, context: context)
        guard case .success(let validated) = LogCommandValidator.validate(result.commands, in: context),
              let first = validated.first else { return nil }
        switch first.command {
        case .logSet(let spec):
            guard let values = spec.sets.first,
                  let index = entryIndex(exercise: spec.exercise, session: session) else { return nil }
            return parse(phrase: phrase, entry: session.exercises[index], session: session) { parsed in
                parsed.weightKg = values.weightKg ?? values.addedKg
                parsed.reps = values.reps
                parsed.effort = spec.effort
                parsed.durationSeconds = values.durationSeconds
            }
        case .repeatPrevious(let overrides):
            guard let index = session.onDeckIndex, let last = context.lastCompleted else { return nil }
            return parse(phrase: phrase, entry: session.exercises[index], session: session) { parsed in
                let base = last.weightKg ?? 0
                parsed.weightKg = overrides.weightKg ?? (overrides.weightDeltaKg.map { base + $0 } ?? base)
                parsed.reps = overrides.reps ?? last.reps
                parsed.effort = overrides.effort ?? last.effort
                parsed.durationSeconds = overrides.durationSeconds ?? last.durationSeconds
            }
        case .completeOnDeck:
            guard let index = session.onDeckIndex else { return nil }
            return parse(phrase: phrase, entry: session.exercises[index], session: session) { _ in }
        default:
            return nil
        }
    }

    private static func parse(
        phrase: String, entry: WorkoutExerciseEntry, session: WorkoutSession,
        fill: (inout WatchVoiceParse) -> Void
    ) -> WatchVoiceParse? {
        guard let set = entry.sets.first(where: { !$0.isDone }) else { return nil }
        let position = SetFormat.position(of: set, in: entry)
        var parsed = WatchVoiceParse(
            phrase: phrase, exerciseID: entry.id, exerciseName: entry.exercise.name,
            setNumber: position.index,
            weightKg: set.weightKg, reps: set.reps, effort: set.effort, durationSeconds: set.cardioSeconds
        )
        fill(&parsed)
        return parsed
    }

    private static func entryIndex(exercise: ExerciseRef?, session: WorkoutSession) -> Int? {
        switch exercise ?? .onDeck {
        case .onDeck: return session.onDeckIndex
        case .id(let id):
            return session.exercises.firstIndex { $0.exercise.id == id && !$0.isComplete }
                ?? session.exercises.lastIndex { $0.exercise.id == id }
        case .spoken: return nil
        }
    }

    // MARK: - Context (mirrors `VoiceLogController.buildContext`)

    static func buildContext(session: WorkoutSession, store: WorkoutStore, unit: WeightUnit) -> ParseContext {
        let equipment = store.activeEquipment()
        let candidates = session.exercises.map { entry in
            ParseContext.ExerciseCandidate(
                id: entry.exercise.id, name: entry.exercise.name, equipment: entry.exercise.equipment,
                isFavorite: entry.exercise.isFavorite, isInSession: true,
                loggingStyle: loggingStyle(for: entry.exercise.loggingStyle),
                grid: store.loadGrid(for: entry.exercise, equipment: equipment)
            )
        }
        let onDeck: ParseContext.OnDeckSet? = session.onDeckIndex.map { index in
            let entry = session.exercises[index]
            return ParseContext.OnDeckSet(
                exerciseID: entry.exercise.id, name: entry.exercise.name,
                loggingStyle: loggingStyle(for: entry.exercise.loggingStyle) ?? .weightReps,
                kind: entry.sets.first(where: { !$0.isDone })?.kind ?? .working,
                grid: store.loadGrid(for: entry.exercise, equipment: equipment),
                incrementKg: entry.exercise.incrementKg
            )
        }
        let bar = session.onDeckIndex.flatMap { session.exercises[$0].exercise.bar }
        return ParseContext(
            unit: unit, onDeck: onDeck, lastCompleted: lastCompleted(in: session),
            sessionExercises: candidates, library: candidates, aliases: aliases(in: session),
            bar: bar, plateSet: equipment.plates
        )
    }

    private static func lastCompleted(in session: WorkoutSession) -> ParseContext.CompletedSetRef? {
        let entry = session.onDeckIndex.map { session.exercises[$0] }
            ?? session.exercises.last { $0.sets.contains(where: \.isDone) }
        guard let entry, let set = entry.sets.last(where: \.isDone) else { return nil }
        return ParseContext.CompletedSetRef(
            exerciseID: entry.exercise.id, setID: set.id, weightKg: set.weightKg, reps: set.reps,
            effort: set.effort, durationSeconds: set.durationSeconds
        )
    }

    private static func aliases(in session: WorkoutSession) -> [String: UUID] {
        var byPhrase: [String: Set<UUID>] = [:]
        for entry in session.exercises {
            let phrase = Tokenizer.words(entry.exercise.name).joined(separator: " ")
            guard !phrase.isEmpty else { continue }
            byPhrase[phrase, default: []].insert(entry.exercise.id)
        }
        return byPhrase.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    private static func loggingStyle(for style: ExerciseInfo.LoggingStyle) -> ParseContext.LoggingStyle? {
        switch style {
        case .weightReps: .weightReps
        case .bodyweightReps, .weightedBodyweight: .bodyweightReps
        case .assisted: .assisted
        case .timedHold: .timedHold
        case .cardio: .cardio
        }
    }
}
