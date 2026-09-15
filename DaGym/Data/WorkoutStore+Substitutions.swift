import Foundation
import GymCore
import SwiftData

/// One rule-based substitution suggestion, ready for `SwapExerciseSheet`.
struct SubstitutionSuggestion: Identifiable {
    var exercise: ExerciseInfo
    /// One line explaining the pick, e.g. "Same muscles, dumbbells only".
    var why: String
    var id: UUID { exercise.id }
}

extension WorkoutStore {
    /// Rule-based substitutes for `exerciseID` (plan §6.6): builds the exercise library, the
    /// active equipment profile's available equipment, and the last-7-days recovery snapshot,
    /// then hands them to `GymCore.Substitutions`. Empty when `exerciseID` isn't found or nothing
    /// in the library qualifies.
    func substitutes(for exerciseID: UUID, reason: SwapReason) -> [SubstitutionSuggestion] {
        let scored = scoredSubstitutes(for: exerciseID, reason: reason)
        let ordered = SubstitutionRankingValidator.ruleOrder(scored)
        return suggestions(from: ordered)
    }

    /// The rule engine's scored candidates themselves — the closed list the on-device coach
    /// may reorder (`CoachLanguageModel.rankSubstitutes`) but never add to.
    func scoredSubstitutes(for exerciseID: UUID, reason: SwapReason) -> [ScoredSubstitute] {
        guard let subjectModel = fetchExerciseModel(id: exerciseID) else { return [] }
        let libraryModels = fetch(Self.liveExercises()).filter(Self.isLive)
        let equipment = Set(activeProfile()?.availableEquipment ?? [])
        return Substitutions.candidates(
            for: substitutionCandidate(for: subjectModel), reason: reason,
            library: libraryModels.map(substitutionCandidate(for:)), available: equipment,
            recoveryMap: recoverySnapshot().map
        )
    }

    /// Resolves a (validated) ranking back to library rows for `SwapExerciseSheet`.
    func suggestions(from ranked: [RankedSubstitute]) -> [SubstitutionSuggestion] {
        let models = fetchExerciseModels(ids: Set(ranked.map(\.candidateID)))
        return ranked.compactMap { pick in
            guard let model = models[pick.candidateID] else { return nil }
            return SubstitutionSuggestion(exercise: exerciseInfo(for: model), why: pick.why)
        }
    }

    /// Every exercise in the library as a `SubstitutionCandidate` — the struggling-exercise coach
    /// rule's substitution pool (`CoachInput.substitutionLibrary`), the same mapping `substitutes`
    /// already applies per mid-workout swap.
    func substitutionCandidates() -> [SubstitutionCandidate] {
        let models = fetch(Self.liveExercises()).filter(Self.isLive)
        return models.map(substitutionCandidate(for:))
    }

    /// Not `private`: `WorkoutStore+Coach.swift` reuses this same mapping for
    /// `CoachLiftSnapshot.substitutionCandidate` and `substitutionCandidates()` above.
    func substitutionCandidate(for model: ExerciseModel) -> SubstitutionCandidate {
        SubstitutionCandidate(
            id: model.id, name: model.name, primary: model.primary, secondary: model.secondary,
            equipment: model.equipment, mechanic: model.mechanic ?? "compound",
            loggingStyle: model.loggingStyle
        )
    }
}
