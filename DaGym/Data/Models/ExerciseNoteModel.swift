import Foundation
import SwiftData

/// How long an exercise note should keep showing up (features.md adopt 5).
enum ExerciseNoteScope: String, CaseIterable, Identifiable {
    /// Lives on the workout's exercise row only (`WorkoutExerciseModel.note`).
    case session
    /// Pinned to the card the next time the exercise is trained, then retires.
    case next
    /// Pinned to the card every session until deleted.
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: "This session"
        case .next: "Next time"
        case .always: "Always"
        }
    }
}

/// A note the lifter left on an exercise beyond the current session — "next time" and
/// "always" notes, plus the history the detail screen lists. CloudKit-legal: no unique
/// constraints, every stored property defaults, no relationships (ids only, like the PR cache).
@Model
final class ExerciseNoteModel {
    var id: UUID = UUID()
    var exerciseID: UUID?
    var text: String = ""
    /// `ExerciseNoteScope` raw value.
    var scope: String = "next"
    var createdAt: Date = Date()
    /// The workout the note was written in, when it was written mid-session.
    var workoutID: UUID?

    init(
        id: UUID = UUID(), exerciseID: UUID? = nil, text: String = "", scope: String = "next",
        createdAt: Date = Date(), workoutID: UUID? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.text = text
        self.scope = scope
        self.createdAt = createdAt
        self.workoutID = workoutID
    }

    var noteScope: ExerciseNoteScope { ExerciseNoteScope(rawValue: scope) ?? .next }
}
