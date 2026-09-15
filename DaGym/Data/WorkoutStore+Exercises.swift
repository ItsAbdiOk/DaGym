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
    /// `Machine` raw value, for a machine/cable exercise that needs one station.
    var machine: String?
}

extension WorkoutStore {
    /// Every library exercise except the tombstones a seed fold left behind
    /// (`ExerciseSeeder.dedupe`) — the base of every "browse the library" read.
    /// NOTE: the tombstone filter is applied in memory by `isLive`, never in the `#Predicate`.
    /// SwiftData does not translate an optional UUID compared against nil — the fetch comes back
    /// empty, which silently emptied the whole library.
    static func liveExercises() -> FetchDescriptor<ExerciseModel> {
        FetchDescriptor<ExerciseModel>()
    }

    /// A row that survived its seed fold, rather than a tombstone kept alive for late CloudKit
    /// children (`ExerciseSeeder.dedupe`).
    static func isLive(_ model: ExerciseModel) -> Bool { model.mergedIntoID == nil }

    /// The live library read once, with each row's search text folded on first use, for a caller
    /// that runs many lookups back to back. `RoutineSeeder` runs ~50 on first launch, and each
    /// one used to re-fetch the ~1 500-row catalogue and re-fold every row's name: 2.9 s on the
    /// main thread of a fresh install (iPhone 16 Pro, Low Power Mode, Debug).
    @MainActor
    final class ExerciseCatalogue {
        /// The store the rows came from — a snapshot never outlives the store that read it.
        unowned let store: WorkoutStore
        let models: [ExerciseModel]
        let bestByExercise: [UUID: PersonalRecordModel]
        lazy var haystacks: [String] = models.map { WorkoutStore.searchHaystack($0) }

        init(
            store: WorkoutStore, models: [ExerciseModel], bestByExercise: [UUID: PersonalRecordModel]
        ) {
            self.store = store
            self.models = models
            self.bestByExercise = bestByExercise
        }
    }

    /// Two fetches — the library and the PR cache — however many `exercises(in:matching:)` calls
    /// follow, and none at all until the next `save()`: the catalogue is cached on the store
    /// keyed on `changeToken`, so the library search re-reading and re-folding ~1 500 rows on
    /// every keystroke (`LibraryView`, `ExercisePickerSheet`) became a dictionary lookup. A
    /// context with unsaved changes is never served from the cache — a row inserted but not yet
    /// saved would otherwise be invisible to the next read.
    func exerciseCatalogue() -> ExerciseCatalogue {
        if let cachedCatalogue, cachedCatalogue.token == changeToken, !context.hasChanges {
            return cachedCatalogue.catalogue
        }
        let state = storeSignposter.beginInterval("exerciseCatalogue")
        defer { storeSignposter.endInterval("exerciseCatalogue", state) }
        let catalogue = ExerciseCatalogue(
            store: self, models: fetch(Self.liveExercises()).filter(Self.isLive),
            bestByExercise: bestE1RMRecordsByExercise()
        )
        cachedCatalogue = (changeToken, catalogue)
        return catalogue
    }

    /// Drops the cached catalogue so the next `exerciseCatalogue()` re-reads the library. `save()`
    /// makes this unnecessary for the store's own writes (the token moves); it is for rows that
    /// arrive without one — a CloudKit import folded by `dedupeSeededRows()` that changed nothing
    /// locally, or a seeder saving through the context directly.
    func invalidateExerciseCatalogue() {
        cachedCatalogue = nil
    }

    /// How many live exercises the library holds — the number `LibraryView`'s header shows. Reads
    /// the cached catalogue, so it costs nothing between saves (a `fetchCount` can't exclude the
    /// fold tombstones: `mergedIntoID == nil` doesn't translate to a predicate, see `liveExercises`).
    func exerciseCount() -> Int {
        exerciseCatalogue().models.count
    }

    /// Filtered, sorted (favorites first, then name) exercise list for the library screen. Best
    /// e1RM comes from one fetch of the PR cache shared by every row; `sessions` is left at 0 —
    /// the detail screen fills it in via `exerciseInfo(for:)`, which is the only place it's shown.
    func exercises(
        matching query: String = "", muscle: Muscle? = nil, equipment: String? = nil,
        favoritesOnly: Bool = false, customOnly: Bool = false
    ) -> [ExerciseInfo] {
        exercises(
            in: exerciseCatalogue(), matching: query, muscle: muscle, equipment: equipment,
            favoritesOnly: favoritesOnly, customOnly: customOnly
        )
    }

    /// `exercises(matching:)` over a catalogue already read — no store round trip.
    func exercises(
        in catalogue: ExerciseCatalogue, matching query: String = "", muscle: Muscle? = nil,
        equipment: String? = nil, favoritesOnly: Bool = false, customOnly: Bool = false
    ) -> [ExerciseInfo] {
        let tokens = Self.searchTokens(query)
        // Folding every row's search text is the expensive part; skip it for an empty query.
        let haystacks = tokens.isEmpty ? nil : catalogue.haystacks
        var matched: [ExerciseModel] = []
        for (index, model) in catalogue.models.enumerated() {
            let haystack = haystacks?[index] ?? ""
            guard matches(model, haystack: haystack, tokens: tokens, muscle: muscle, equipment: equipment)
            else { continue }
            if favoritesOnly, !model.isFavorite { continue }
            if customOnly, !model.isCustom { continue }
            matched.append(model)
        }
        return matched
            .sorted(by: sortsBeforeInLibrary)
            .map { model in
                var info = ExerciseInfo(model: model)
                if let best = catalogue.bestByExercise[model.id] {
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
        _ model: ExerciseModel, haystack: String, tokens: [String], muscle: Muscle?, equipment: String?
    ) -> Bool {
        let nameMatches = tokens.isEmpty || tokens.allSatisfy { haystack.contains($0) }
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
    /// `facts`, when passed, already holds both stats for every exercise — one query each for
    /// the whole session rather than two per exercise (see `SessionFacts`).
    func exerciseInfo(for model: ExerciseModel, facts: SessionFacts? = nil) -> ExerciseInfo {
        var info = ExerciseInfo(model: model)
        let best: PersonalRecordModel?
        if let facts {
            best = facts.bestE1RM[model.id]
            info.sessions = facts.sessionCounts[model.id] ?? 0
        } else {
            best = bestE1RMRecord(exerciseID: model.id)
            info.sessions = sessionCount(exerciseID: model.id)
        }
        info.bestE1RM = best?.value
        info.bestSet = best.map(Self.bestSetLine)
        return info
    }

    private static func bestSetLine(_ record: PersonalRecordModel) -> String {
        "\(WorkoutSession.format(record.weightKg))×\(record.reps)"
    }

    @discardableResult
    func createCustomExercise(
        name: String, primary: [Muscle], equipment: String, style: ExerciseInfo.LoggingStyle,
        isPerSide: Bool = false, barType: String? = nil, machine: String? = nil
    ) -> ExerciseInfo {
        // `restSeconds: 0` means "use Settings → Default rest"; the lifter can override it per
        // exercise from Exercise Detail.
        let model = ExerciseModel(
            name: name, primaryMuscles: primary.map(\.rawValue), equipment: equipment,
            loggingStyle: style.rawKey, isPerSide: isPerSide, isCustom: true, barType: barType,
            restSeconds: 0, machine: machine
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
        model.machine = fields.machine
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
        let records = fetch(FetchDescriptor(predicate: predicate))
        return records.max { $0.value < $1.value }
    }

    /// The best cached e1RM row per exercise, in one fetch, for list screens and `SessionFacts`.
    func bestE1RMRecordsByExercise() -> [UUID: PersonalRecordModel] {
        let predicate = #Predicate<PersonalRecordModel> { $0.kind == "e1rm" }
        let records = fetch(FetchDescriptor(predicate: predicate))
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
        return fetchCount(FetchDescriptor(predicate: predicate))
    }
}

extension WorkoutStore {
    /// The library exercise carrying this seed id, for the import alias table. Nil when the row
    /// was deleted or the id isn't in this seed version.
    func exerciseID(seedID: String) -> UUID? {
        let descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.seedID == seedID })
        return fetch(descriptor).first { $0.mergedIntoID == nil }?.id
    }
}
