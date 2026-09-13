import Foundation
import GymCore
import SwiftData

/// The editable identity of a custom exercise, as `updateCustomExercise` writes it.
struct CustomExerciseFields {
    var name: String
    var primary: [Muscle]
    var equipment: String
    var style: ExerciseInfo.LoggingStyle
    var isPerSide = false
    var barType: String?
}

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

    /// Edits a custom exercise's identity fields (features.md adopt 16). Seeded exercises are
    /// left alone — their instructions/muscles come from the seed.
    func updateCustomExercise(id: UUID, fields: CustomExerciseFields) {
        guard let model = fetchExerciseModel(id: id), model.isCustom else { return }
        model.name = fields.name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.primaryMuscles = fields.primary.map(\.rawValue)
        model.equipment = fields.equipment
        model.loggingStyle = fields.style.rawKey
        model.isPerSide = fields.isPerSide
        model.barType = fields.barType
        save()
    }

    /// Removes a custom exercise and its slots in every routine; finished workouts keep their
    /// rows (the exercise link nulls out) so history totals don't change. Seeded exercises can't
    /// be deleted. Returns whether anything was removed.
    @discardableResult
    func deleteCustomExercise(id: UUID) -> Bool {
        guard let model = fetchExerciseModel(id: id), model.isCustom else { return false }
        for slot in model.routineExercises ?? [] {
            context.delete(slot)
        }
        context.delete(model)
        save()
        WidgetSnapshotWriter.refresh(store: self)
        return true
    }

    /// The (unarchived) routines that include this exercise — the "used in N routines" warning
    /// before a delete.
    func routinesUsing(exerciseID: UUID) -> [RoutineInfo] {
        routines().filter { routine in routine.exercises.contains { $0.id == exerciseID } }
    }

    /// Appends the exercise to the end of a routine with `sets` planned working sets in the
    /// routine's rep range. A no-op when either id is unknown.
    func addExercise(id exerciseID: UUID, toRoutine routineID: UUID, sets: Int = 3) {
        guard let routine = fetchRoutineModel(id: routineID),
              let exercise = fetchExerciseModel(id: exerciseID) else { return }
        let order = ((routine.exercises ?? []).map(\.order).max() ?? -1) + 1
        let slot = RoutineExerciseModel(order: order, exercise: exercise, routine: routine)
        context.insert(slot)
        slot.plannedSets = (0..<max(1, sets)).map { index in
            let planned = PlannedSetModel(
                order: index, kind: SetKind.working.rawValue, targetReps: routine.repRangeLow,
                targetRepsHigh: routine.repRangeHigh, routineExercise: slot
            )
            context.insert(planned)
            return planned
        }
        routine.updatedAt = Date()
        save()
        WidgetSnapshotWriter.refresh(store: self)
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
