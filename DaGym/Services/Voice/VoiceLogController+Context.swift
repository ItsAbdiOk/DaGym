import Foundation
import GymCore

/// `WorkoutSession` → `GymCore.ParseContext`, and `LogCommand`/`LogSetSpec` back onto the
/// session's own `WorkoutExerciseEntry`/`SetEntry` indices.
extension VoiceLogController {
    /// `ParseContext.library` is scoped to the current session (not the full exercise library) —
    /// deliberately: it's what lets `VoiceLogController+Errors.swift` tell "not in this session"
    /// apart from "ambiguous between two session exercises" without a separate library lookup.
    static func buildContext(session: WorkoutSession, preferences: Preferences) -> ParseContext {
        let candidates = session.exercises.map { entry in
            ParseContext.ExerciseCandidate(
                id: entry.exercise.id, name: entry.exercise.name, equipment: entry.exercise.equipment,
                isFavorite: entry.exercise.isFavorite, isInSession: true,
                loggingStyle: loggingStyle(for: entry.exercise.loggingStyle)
            )
        }
        let onDeck: ParseContext.OnDeckSet? = session.onDeckIndex.map { index in
            let entry = session.exercises[index]
            return ParseContext.OnDeckSet(
                exerciseID: entry.exercise.id, name: entry.exercise.name,
                loggingStyle: loggingStyle(for: entry.exercise.loggingStyle) ?? .weightReps,
                kind: entry.sets.first(where: { !$0.isDone })?.kind ?? .working,
                incrementKg: entry.exercise.incrementKg
            )
        }
        let bar = session.onDeckIndex.flatMap { session.exercises[$0].exercise.bar }
        return ParseContext(
            unit: preferences.weightUnit, onDeck: onDeck, sessionExercises: candidates,
            library: candidates, bar: bar
        )
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
    static func resolveEntryIndex(exercise: ExerciseRef?, session: WorkoutSession) -> Int? {
        switch exercise ?? .onDeck {
        case .onDeck:
            return session.onDeckIndex
        case .id(let exerciseID):
            if let onDeck = session.onDeckIndex, session.exercises[onDeck].exercise.id == exerciseID {
                return onDeck
            }
            return session.exercises.firstIndex { $0.exercise.id == exerciseID }
        case .spoken:
            return nil
        }
    }

    /// The set a spec's values land on: the first not-done set of the requested kind, or (every
    /// planned set already done) a freshly appended one via `WorkoutSession.addSet` — the same
    /// call the "Add set" menu action makes.
    static func targetSetIndex(
        entryIndex: Int, kind: SetKind?, session: WorkoutSession
    ) -> (index: Int, wasInserted: Bool) {
        if let index = session.exercises[entryIndex].sets.firstIndex(where: { !$0.isDone }) {
            return (index, false)
        }
        session.addSet(exerciseID: session.exercises[entryIndex].id, kind: kind ?? .working)
        return (session.exercises[entryIndex].sets.count - 1, true)
    }

    static func summary(exerciseName: String, weightKg: Double, reps: Int) -> String {
        let weightText = weightKg == weightKg.rounded()
            ? String(Int(weightKg)) : String(format: "%.1f", weightKg)
        return "\(exerciseName) · \(weightText) kg × \(reps)"
    }
}
