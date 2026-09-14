import Foundation
import GymCore

/// `WorkoutSession` → `GymCore.ParseContext`, and `LogCommand`/`LogSetSpec` back onto the
/// session's own `WorkoutExerciseEntry`/`SetEntry` indices.
extension VoiceLogController {
    /// `ParseContext.library` is scoped to the current session (not the full exercise library) —
    /// deliberately: it's what lets `VoiceLogController+Errors.swift` tell "not in this session"
    /// apart from "ambiguous between two session exercises" without a separate library lookup.
    ///
    /// `lastCompleted`, `aliases`, `plateSet` and each candidate's `grid` are all filled in here.
    /// They used to be left at their defaults, which quietly disabled half of
    /// `LogCommandValidator`: with no `lastCompleted` the suspicious-jump and
    /// "reps doubled" checks can never fire, so "no validator warnings" was a vacuous condition
    /// for auto-logging, and with no per-exercise grid every weight rounded against a generic
    /// step or the bar.
    static func buildContext(
        session: WorkoutSession, store: WorkoutStore, preferences: Preferences
    ) -> ParseContext {
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
            unit: preferences.weightUnit, onDeck: onDeck, lastCompleted: lastCompleted(in: session),
            sessionExercises: candidates, library: candidates, aliases: aliases(in: session),
            bar: bar, plateSet: equipment.plates
        )
    }

    /// The set `LogCommandValidator`'s plausibility checks compare against. `ParseContext` holds
    /// exactly one, and the validator only uses it when it belongs to the exercise being logged,
    /// so the on-deck exercise's own last completed set is the useful choice; failing that, the
    /// last completed set anywhere in the session. `SetEntry` carries no completion timestamp, so
    /// "last" means session order — the order sets are performed in.
    static func lastCompleted(in session: WorkoutSession) -> ParseContext.CompletedSetRef? {
        if let index = session.onDeckIndex,
           let set = session.exercises[index].sets.last(where: \.isDone) {
            return completedRef(set, exercise: session.exercises[index].exercise)
        }
        for entry in session.exercises.reversed() {
            if let set = entry.sets.last(where: \.isDone) {
                return completedRef(set, exercise: entry.exercise)
            }
        }
        return nil
    }

    private static func completedRef(
        _ set: SetEntry, exercise: ExerciseInfo
    ) -> ParseContext.CompletedSetRef {
        ParseContext.CompletedSetRef(
            exerciseID: exercise.id, setID: set.id, weightKg: set.weightKg, reps: set.reps,
            effort: set.effort, durationSeconds: set.durationSeconds
        )
    }

    /// An exact spoken exercise name short-circuits `ExerciseMatcher` at score 1.0 instead of
    /// competing on fuzzy similarity with everything else in the session. Only unambiguous names
    /// are included: if two entries normalise to the same phrase but are different exercises,
    /// that phrase stays a disambiguation prompt.
    static func aliases(in session: WorkoutSession) -> [String: UUID] {
        var byPhrase: [String: Set<UUID>] = [:]
        for entry in session.exercises {
            let phrase = Tokenizer.words(entry.exercise.name).joined(separator: " ")
            guard !phrase.isEmpty else { continue }
            byPhrase[phrase, default: []].insert(entry.exercise.id)
        }
        return byPhrase.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    static func loggingStyle(for style: ExerciseInfo.LoggingStyle) -> ParseContext.LoggingStyle? {
        switch style {
        case .weightReps: .weightReps
        case .bodyweightReps, .weightedBodyweight: .bodyweightReps
        case .assisted: .assisted
        case .timedHold: .timedHold
        case .cardio: nil
        }
    }

    /// The session row an `ExerciseRef` refers to. `.spoken` never resolves here — the validator
    /// already rejects it (`.needsDisambiguation`) before this is reached.
    ///
    /// An exercise can appear more than once in a session (a superset, an A/C block). Taking the
    /// first match appended the set to the block the lifter had already finished; the row they
    /// mean is the one still waiting for work.
    static func resolveEntryIndex(exercise: ExerciseRef?, session: WorkoutSession) -> Int? {
        switch exercise ?? .onDeck {
        case .onDeck:
            return session.onDeckIndex
        case .id(let exerciseID):
            if let onDeck = session.onDeckIndex, session.exercises[onDeck].exercise.id == exerciseID {
                return onDeck
            }
            let pending = session.exercises.firstIndex {
                $0.exercise.id == exerciseID && !$0.isComplete
            }
            // Every block of this exercise is finished: the last one is the one just worked, so
            // an extra set belongs there rather than back in the first block of the session.
            return pending ?? session.exercises.lastIndex { $0.exercise.id == exerciseID }
        case .spoken:
            return nil
        }
    }

    /// The set a spec's values land on.
    ///
    /// With a spoken set kind ("drop set 60 for 12") the target must be a set of *that* kind:
    /// stamping the kind onto the next planned working set converted a planned working set into
    /// a drop set and lost the planned one. When there's no open set of that kind, a new one is
    /// appended via `WorkoutSession.addSet` — the same call the "Add set" menu action makes.
    /// With no kind spoken, the next open set of any kind is the target, as before.
    static func targetSetIndex(
        entryIndex: Int, kind: SetKind?, session: WorkoutSession
    ) -> (index: Int, wasInserted: Bool) {
        let sets = session.exercises[entryIndex].sets
        if let kind {
            if let index = sets.firstIndex(where: { !$0.isDone && $0.kind == kind }) {
                return (index, false)
            }
        } else if let index = sets.firstIndex(where: { !$0.isDone }) {
            return (index, false)
        }
        session.addSet(exerciseID: session.exercises[entryIndex].id, kind: kind ?? .working)
        return (session.exercises[entryIndex].sets.count - 1, true)
    }

    /// The toast and the spoken confirmation, in the user's own unit. Hardcoding "kg" told an
    /// lb lifter their 225 lb bench was "102 kg".
    static func summary(
        exerciseName: String, weightKg: Double, reps: Int, unit: WeightUnit
    ) -> String {
        "\(exerciseName) · \(unit.format(kg: weightKg)) \(unit.symbol) × \(reps)"
    }
}
