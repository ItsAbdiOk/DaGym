import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// Filtered, sorted (favorites first, then name) exercise list for the library screen.
    func exercises(
        matching query: String = "", muscle: Muscle? = nil, equipment: String? = nil,
        favoritesOnly: Bool = false, customOnly: Bool = false
    ) -> [ExerciseInfo] {
        let all = (try? context.fetch(FetchDescriptor<ExerciseModel>())) ?? []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all
            .filter { matches($0, trimmed: trimmed, muscle: muscle, equipment: equipment) }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { !customOnly || $0.isCustom }
            .sorted(by: sortsBeforeInLibrary)
            .map(exerciseInfo(for:))
    }

    private func matches(
        _ model: ExerciseModel, trimmed: String, muscle: Muscle?, equipment: String?
    ) -> Bool {
        let nameMatches = trimmed.isEmpty || model.name.lowercased().contains(trimmed)
        let muscleMatches = muscle.map { model.primary.contains($0) || model.secondary.contains($0) } ?? true
        let equipmentMatches = equipment.map { model.equipment == $0 } ?? true
        return nameMatches && muscleMatches && equipmentMatches
    }

    private func sortsBeforeInLibrary(_ lhs: ExerciseModel, _ rhs: ExerciseModel) -> Bool {
        if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// Maps a model plus its computed stats (best e1RM, best set line, session count).
    func exerciseInfo(for model: ExerciseModel) -> ExerciseInfo {
        var info = ExerciseInfo(model: model)
        let best = bestE1RMRecord(exerciseID: model.id)
        info.bestE1RM = best?.value
        info.bestSet = best.map { "\(WorkoutSession.format($0.weightKg))×\($0.reps)" }
        info.sessions = sessionCount(exerciseID: model.id)
        return info
    }

    @discardableResult
    func createCustomExercise(
        name: String, primary: [Muscle], equipment: String, style: ExerciseInfo.LoggingStyle
    ) -> ExerciseInfo {
        let model = ExerciseModel(
            name: name, primaryMuscles: primary.map(\.rawValue), equipment: equipment,
            loggingStyle: style.rawKey, isCustom: true
        )
        context.insert(model)
        save()
        return exerciseInfo(for: model)
    }

    func toggleFavorite(id: UUID) {
        guard let model = fetchExerciseModel(id: id) else { return }
        model.isFavorite.toggle()
        save()
    }

    // MARK: - Stats

    /// The cached e1RM personal record for an exercise, if one exists.
    /// Swap for a `GymCore.PersonalRecords` cache read once the shared module lands (lead's note).
    func bestE1RMRecord(exerciseID: UUID) -> PersonalRecordModel? {
        let predicate = #Predicate<PersonalRecordModel> { $0.exerciseID == exerciseID && $0.kind == "e1rm" }
        let records = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        return records.max { $0.value < $1.value }
    }

    private func sessionCount(exerciseID: UUID) -> Int {
        let predicate = #Predicate<WorkoutExerciseModel> { $0.exercise?.id == exerciseID }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }
}
