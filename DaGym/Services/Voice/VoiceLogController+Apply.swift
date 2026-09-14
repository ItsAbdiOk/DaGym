import Foundation
import GymCore

/// The one mutation path a validated `logSet`/`completeOnDeck` command goes through — shared by
/// auto-log and the review card's "Log" button, and always ending in `store.sync(session:)`, the
/// same call every other mutation in `ActiveWorkoutView+Actions` makes.
/// Where a validated spec is written: the live session, the store that persists it, and the unit
/// the confirmation is phrased in (a spoken set is logged in kg but confirmed in the user's own
/// unit). Bundled so `apply` stays inside the parameter-count cap.
struct VoiceLogWriteTarget {
    var session: WorkoutSession
    var store: WorkoutStore
    var unit: WeightUnit
}

extension VoiceLogController {
    struct ApplyResult {
        var summary: String
        var undo: () -> Void
    }

    /// Fills each of `spec.sets` into the next open (or freshly inserted) set on the target
    /// exercise and completes it via `WorkoutSession.completeSet` — the exact call
    /// `ActiveWorkoutView+Actions.toggleDone` makes for a tap on the checkmark.
    func apply(
        spec: LogSetSpec, entryIndex: Int, target: VoiceLogWriteTarget,
        completion: (ApplyResult) -> Void
    ) {
        let session = target.session
        let store = target.store
        let entryID = session.exercises[entryIndex].id
        var snapshots: [VoiceLogSetSnapshot] = []
        var lastSummary = ""

        for values in spec.sets {
            let (setIndex, wasInserted) = Self.targetSetIndex(
                entryIndex: entryIndex, kind: spec.kind, session: session
            )
            let setID = session.exercises[entryIndex].sets[setIndex].id
            let before = session.exercises[entryIndex].sets[setIndex]

            if let weight = values.weightKg { session.exercises[entryIndex].sets[setIndex].weightKg = weight }
            if let reps = values.reps { session.exercises[entryIndex].sets[setIndex].reps = reps }
            if let duration = values.durationSeconds {
                session.exercises[entryIndex].sets[setIndex].durationSeconds = duration
            }
            if let assistance = values.assistanceKg {
                session.exercises[entryIndex].sets[setIndex].assistanceKg = assistance
            }
            // `targetSetIndex` already picked (or appended) a set of this kind, so this only
            // re-affirms it — it must never be the thing that converts a planned working set.
            if let kind = spec.kind { session.exercises[entryIndex].sets[setIndex].kind = kind }

            session.completeSet(exerciseID: entryID, setID: setID, effort: spec.effort)
            snapshots.append(
                VoiceLogSetSnapshot(
                    entryID: entryID, setID: setID, previous: before, wasInserted: wasInserted
                )
            )
            lastSummary = Self.summary(
                exerciseName: session.exercises[entryIndex].exercise.name,
                weightKg: session.exercises[entryIndex].sets[setIndex].weightKg,
                reps: session.exercises[entryIndex].sets[setIndex].reps, unit: target.unit
            )
        }

        store.sync(session: session)
        completion(ApplyResult(summary: lastSummary, undo: { [weak store] in
            Self.undo(snapshots, session: session)
            store?.sync(session: session)
        }))
    }

    /// "Done"/"next": completes the on-deck set as prefilled, no field overrides.
    func applyCompleteOnDeck(
        session: WorkoutSession, store: WorkoutStore, preferences: Preferences,
        undo: @escaping (UndoAction) -> Void
    ) {
        guard let entryIndex = session.onDeckIndex,
              let setIndex = session.exercises[entryIndex].sets.firstIndex(where: { !$0.isDone }) else {
            state = .error(.unsupportedCommand)
            return
        }
        let entryID = session.exercises[entryIndex].id
        let set = session.exercises[entryIndex].sets[setIndex]
        session.completeSet(exerciseID: entryID, setID: set.id)
        store.sync(session: session)
        let summary = Self.summary(
            exerciseName: session.exercises[entryIndex].exercise.name, weightKg: set.weightKg,
            reps: set.reps, unit: preferences.weightUnit
        )
        let snapshot = VoiceLogSetSnapshot(entryID: entryID, setID: set.id, previous: set, wasInserted: false)
        undo(UndoAction(message: summary, undo: { [weak store] in
            Self.undo([snapshot], session: session)
            store?.sync(session: session)
        }))
        state = .autoLogged(message: summary)
        if preferences.voiceSpeakBackOnHeadphones { speakBack(summary) }
    }

    static func undo(_ snapshots: [VoiceLogSetSnapshot], session: WorkoutSession) {
        for snapshot in snapshots.reversed() {
            guard let entryIndex = session.exercises.firstIndex(where: { $0.id == snapshot.entryID }) else {
                continue
            }
            if snapshot.wasInserted {
                session.exercises[entryIndex].sets.removeAll { $0.id == snapshot.setID }
            } else if let setIndex = session.exercises[entryIndex].sets.firstIndex(where: {
                $0.id == snapshot.setID
            }) {
                session.exercises[entryIndex].sets[setIndex] = snapshot.previous
            }
        }
    }

    /// Speaks a short confirmation via `AVSpeechSynthesis`. Callers already checked
    /// `Preferences.voiceSpeakBackOnHeadphones`; this only gates on the route — silent unless
    /// audio is currently going to headphones/AirPods.
    func speakBack(_ message: String) {
        guard speaker.isRoutedToHeadphones else { return }
        speaker.speak(message)
    }
}
