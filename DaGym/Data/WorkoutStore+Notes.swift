import Foundation
import SwiftData

/// One note on an exercise as the detail screen and the card read it — a "next time"/"always"
/// row from `ExerciseNoteModel`, or a session note carried on a finished workout's exercise row.
struct ExerciseNoteInfo: Identifiable, Hashable {
    let id: UUID
    var text: String
    var scope: ExerciseNoteScope
    var createdAt: Date
    var workoutID: UUID?
}

/// Exercise notes with scope (features.md adopt 5). Session notes stay on
/// `WorkoutExerciseModel.note`; "next time" and "always" notes are their own rows so they
/// outlive the workout they were written in.
extension WorkoutStore {
    /// Stores a `.next` or `.always` note. A `.session` scope is the caller's to keep on the
    /// workout row, so it's ignored here. Blank text is ignored too.
    @discardableResult
    func addExerciseNote(
        exerciseID: UUID, text: String, scope: ExerciseNoteScope, workoutID: UUID? = nil,
        createdAt: Date = Date()
    ) -> ExerciseNoteInfo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scope != .session, !trimmed.isEmpty else { return nil }
        let model = ExerciseNoteModel(
            exerciseID: exerciseID, text: trimmed, scope: scope.rawValue, createdAt: createdAt,
            workoutID: workoutID
        )
        context.insert(model)
        save()
        return Self.noteInfo(model)
    }

    /// An "always" note the coach chat saves from a reply. Saving the same text twice (the
    /// lifter long-presses the bubble again) keeps the one note rather than stacking a twin;
    /// the existing note comes back so the caller can still confirm.
    @discardableResult
    func addCoachExerciseNote(exerciseID: UUID, text: String, createdAt: Date = Date()) -> ExerciseNoteInfo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = scopedNotes(exerciseID: exerciseID)
            .first(where: { $0.noteScope == .always && $0.text == trimmed }) {
            return Self.noteInfo(existing)
        }
        return addExerciseNote(exerciseID: exerciseID, text: trimmed, scope: .always, createdAt: createdAt)
    }

    func deleteExerciseNote(id: UUID) {
        let predicate = #Predicate<ExerciseNoteModel> { $0.id == id }
        guard let model = fetchFirst(FetchDescriptor(predicate: predicate)) else { return }
        context.delete(model)
        save()
    }

    /// Every note ever left on the exercise, newest first: scoped notes plus the session notes
    /// on finished workouts that trained it.
    func exerciseNotes(exerciseID: UUID) -> [ExerciseNoteInfo] {
        let scoped = scopedNotes(exerciseID: exerciseID).map(Self.noteInfo)
        let predicate = #Predicate<WorkoutExerciseModel> {
            $0.exercise?.id == exerciseID && $0.workout?.endedAt != nil && !$0.note.isEmpty
        }
        let rows = fetch(FetchDescriptor(predicate: predicate))
        let sessionNotes = rows.compactMap { row -> ExerciseNoteInfo? in
            guard let workout = row.workout else { return nil }
            return ExerciseNoteInfo(
                id: row.id, text: row.note, scope: .session, createdAt: workout.startedAt,
                workoutID: workout.id
            )
        }
        return (scoped + sessionNotes).sorted { $0.createdAt > $1.createdAt }
    }

    /// The note to pin on the exercise's card in workout `workoutID`: the newest "always" note,
    /// else the newest "next time" note that hasn't had its next session yet. A "next time" note
    /// counts as spent once a *finished* workout other than the one it was written in has trained
    /// the exercise since it was written — so it shows through the whole of that next session
    /// and is gone the one after.
    func pinnedNote(exerciseID: UUID, workoutID: UUID? = nil) -> ExerciseNoteInfo? {
        let notes = scopedNotes(exerciseID: exerciseID)
        if let always = notes.first(where: { $0.noteScope == .always }) { return Self.noteInfo(always) }
        guard let next = notes.first(where: { $0.noteScope == .next }) else { return nil }
        let since = next.createdAt
        let authorWorkoutID = next.workoutID
        let predicate = #Predicate<WorkoutExerciseModel> {
            $0.exercise?.id == exerciseID && $0.workout?.endedAt != nil
        }
        let trained = fetch(FetchDescriptor(predicate: predicate))
        let spentBy = trained.compactMap(\.workout)
            .filter { $0.startedAt > since && $0.id != authorWorkoutID && $0.id != workoutID }
        return spentBy.isEmpty ? Self.noteInfo(next) : nil
    }

    /// Newest first.
    private func scopedNotes(exerciseID: UUID) -> [ExerciseNoteModel] {
        let descriptor = FetchDescriptor<ExerciseNoteModel>(
            predicate: #Predicate { $0.exerciseID == exerciseID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return fetch(descriptor)
    }

    private static func noteInfo(_ model: ExerciseNoteModel) -> ExerciseNoteInfo {
        ExerciseNoteInfo(
            id: model.id, text: model.text, scope: model.noteScope, createdAt: model.createdAt,
            workoutID: model.workoutID
        )
    }
}
