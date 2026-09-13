import AppIntents
import Foundation

/// Siri/Shortcuts-facing exercise reference (voice-logging-plan.md §6.2), resolved by the same
/// `GymCore.ExerciseMatcher` fuzzy matcher text/voice logging uses (via `IntentFormatting`), so
/// "last bench" in Siri and "log a set: bench" in the app agree on what "bench" means.
struct ExerciseEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Exercise"
    static let defaultQuery = ExerciseEntityQuery()

    var id: UUID
    var name: String
    var equipment: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(equipment)")
    }
}

/// Backed by the process-wide store (`IntentStoreAccess`) plus the pure
/// `IntentFormatting.matchingExercises` ranker — Siri's own text-field resolution for
/// `\(\.$exercise)` calls `entities(matching:)` as the user types, so each call must be cheap:
/// no container is opened here, only one exercise fetch.
struct ExerciseEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [ExerciseEntity.ID]) async throws -> [ExerciseEntity] {
        candidates().filter { identifiers.contains($0.id) }.map(Self.entity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ExerciseEntity] {
        IntentFormatting.matchingExercises(string, in: candidates()).map(Self.entity)
    }

    /// Favorites first, for Siri's own "did you mean…" suggestion list when the parameter is
    /// still unresolved.
    @MainActor
    func suggestedEntities() async throws -> [ExerciseEntity] {
        guard let store = IntentStoreAccess.makeStore() else { return [] }
        return store.exercises(favoritesOnly: true).prefix(5).map {
            ExerciseEntity(id: $0.id, name: $0.name, equipment: $0.equipment)
        }
    }

    @MainActor
    private func candidates() -> [IntentFormatting.ExerciseCandidate] {
        guard let store = IntentStoreAccess.makeStore() else { return [] }
        return store.exercises(matching: "").map {
            IntentFormatting.ExerciseCandidate(id: $0.id, name: $0.name, equipment: $0.equipment)
        }
    }

    private static func entity(_ candidate: IntentFormatting.ExerciseCandidate) -> ExerciseEntity {
        ExerciseEntity(id: candidate.id, name: candidate.name, equipment: candidate.equipment ?? "other")
    }
}
