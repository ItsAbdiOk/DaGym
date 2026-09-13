import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// Filtered, sorted (favorites first, then name) exercise list for the library screen. Best
    /// e1RM comes from one fetch of the PR cache shared by every row; `sessions` is left at 0 —
    /// the detail screen fills it in via `exerciseInfo(for:)`, which is the only place it's shown.
    func exercises(
        matching query: String = "", muscle: Muscle? = nil, equipment: String? = nil,
        favoritesOnly: Bool = false, customOnly: Bool = false
    ) -> [ExerciseInfo] {
        let all = (try? context.fetch(FetchDescriptor<ExerciseModel>())) ?? []
        let tokens = Self.searchTokens(query)
        let bestByExercise = bestE1RMRecordsByExercise()
        return all
            .filter { matches($0, tokens: tokens, muscle: muscle, equipment: equipment) }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { !customOnly || $0.isCustom }
            .sorted(by: sortsBeforeInLibrary)
            .map { model in
                var info = ExerciseInfo(model: model)
                if let best = bestByExercise[model.id] {
                    info.bestE1RM = best.value
                    info.bestSet = Self.bestSetLine(best)
                }
                return info
            }
    }

    /// Every query token must appear somewhere in the exercise's name, muscles, equipment or
    /// logging style — "chest dumbbell" finds Dumbbell Bench Press, "pullover" finds
    /// "Dumbbell Pull-Over". Accents and case are ignored; "db"/"bb"/"kb" expand first.
    private func matches(
        _ model: ExerciseModel, tokens: [String], muscle: Muscle?, equipment: String?
    ) -> Bool {
        let nameMatches = tokens.isEmpty || {
            let haystack = Self.searchHaystack(model)
            return tokens.allSatisfy { haystack.contains($0) }
        }()
        let muscleMatches = muscle.map { model.primary.contains($0) || model.secondary.contains($0) } ?? true
        let equipmentMatches = equipment.map { model.equipment == $0 } ?? true
        return nameMatches && muscleMatches && equipmentMatches
    }

    private static let searchAliases = ["db": "dumbbell", "bb": "barbell", "kb": "kettlebell"]

    static func searchTokens(_ query: String) -> [String] {
        searchFold(query).split(whereSeparator: \.isWhitespace)
            .map { searchAliases[String($0)] ?? String($0) }
    }

    private static func searchHaystack(_ model: ExerciseModel) -> String {
        let muscles = (model.primary + model.secondary).map(\.displayName)
        return searchFold(
            ([model.name, model.equipment, model.style.rawValue] + muscles).joined(separator: " ")
        )
    }

    private static func searchFold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "-", with: "")
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
        info.bestSet = best.map(Self.bestSetLine)
        info.sessions = sessionCount(exerciseID: model.id)
        return info
    }

    private static func bestSetLine(_ record: PersonalRecordModel) -> String {
        "\(WorkoutSession.format(record.weightKg))×\(record.reps)"
    }

    @discardableResult
    func createCustomExercise(
        name: String, primary: [Muscle], equipment: String, style: ExerciseInfo.LoggingStyle,
        isPerSide: Bool = false, barType: String? = nil
    ) -> ExerciseInfo {
        let model = ExerciseModel(
            name: name, primaryMuscles: primary.map(\.rawValue), equipment: equipment,
            loggingStyle: style.rawKey, isPerSide: isPerSide, isCustom: true, barType: barType
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

    /// Updates the per-exercise reference settings shown on the detail screen.
    func updateExerciseSettings(id: UUID, restSeconds: Int, barType: String?, incrementKg: Double) {
        guard let model = fetchExerciseModel(id: id) else { return }
        model.restSeconds = restSeconds
        model.barType = barType
        model.incrementKg = incrementKg
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

    /// The best cached e1RM row per exercise, in one fetch, for list screens.
    private func bestE1RMRecordsByExercise() -> [UUID: PersonalRecordModel] {
        let predicate = #Predicate<PersonalRecordModel> { $0.kind == "e1rm" }
        let records = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        var best: [UUID: PersonalRecordModel] = [:]
        for record in records {
            guard let exerciseID = record.exerciseID else { continue }
            if let current = best[exerciseID], current.value >= record.value { continue }
            best[exerciseID] = record
        }
        return best
    }

    /// Finished workouts only: an in-progress (or abandoned) session isn't a session yet.
    private func sessionCount(exerciseID: UUID) -> Int {
        let predicate = #Predicate<WorkoutExerciseModel> {
            $0.exercise?.id == exerciseID && $0.workout?.endedAt != nil
        }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }
}
