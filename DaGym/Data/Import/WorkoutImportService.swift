import Foundation
import GymCore
import SwiftData

/// What a parsed CSV would add, shown by `ImportSettingsSection` before the user confirms
/// (plan.md §6.8: "show a preview + problems before confirming").
struct ImportPreview: Sendable {
    var source: ImportSource
    var workouts: [ImportedWorkout]
    var setsCount: Int
    /// Exercise names in the file that don't confidently match anything in the library — these
    /// become custom exercises on `apply`.
    var unmatchedExerciseNames: [String]
    /// What every *matched* name will actually be logged against. A wrong match ("Deadlift
    /// (Dumbbell)" landing on the barbell deadlift) is invisible until the history is already
    /// merged, so the preview names both sides and lets the user back out first.
    var matchedExercises: [MatchedExercise] = []
    /// How many of `workouts` are already in the store and will be skipped. Showing a flat
    /// "12 workouts" when all twelve will be skipped is a lie the user only discovers afterwards.
    var alreadyImportedCount = 0
    /// The file's weight column named no unit; `weightUnit` is what the parse assumed.
    var weightUnitAssumed = false
    var weightUnit: WeightUnit = .kg
    var problems: [ImportProblem]

    /// Workouts that will actually be inserted.
    var newWorkoutCount: Int { max(workouts.count - alreadyImportedCount, 0) }
}

/// One source name and the library exercise it resolved to, for the preview list.
struct MatchedExercise: Hashable, Sendable {
    var sourceName: String
    var libraryName: String
}

/// Counts from `WorkoutImportService.apply`, named distinctly from `Data/Backup`'s
/// `ImportReport` (same module, different feature) so the two never collide.
struct WorkoutImportReport: Equatable, Sendable {
    var workoutsImported = 0
    var workoutsSkipped = 0
    var setsImported = 0
    var exercisesCreated = 0
    var problems: [String] = []

    /// "12 workouts, 48 sets, 2 new exercises · 1 problem" for the result footnote.
    var summary: String {
        let parts = [
            countPhrase(workoutsImported, singular: "workout"),
            countPhrase(setsImported, singular: "set"),
            countPhrase(exercisesCreated, singular: "new exercise")
        ].compactMap { $0 }
        var text = parts.isEmpty ? "Nothing new to import" : parts.joined(separator: ", ")
        if !problems.isEmpty {
            text += " · \(countPhrase(problems.count, singular: "problem") ?? "")"
        }
        return text
    }

    private func countPhrase(_ count: Int, singular: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

/// Turns a third-party CSV export into `WorkoutModel`s. Matching uses the same
/// `GymCore.ExerciseMatcher` the voice pipeline uses, but at a stricter threshold (0.85 vs. the
/// matcher's own 0.82) since there's no user in the loop here to disambiguate a bad guess.
@MainActor
enum WorkoutImportService {
    /// The score a match must clear to be used automatically; below this, the exercise is
    /// reported as unmatched (preview) and created as custom (apply).
    nonisolated static let matchThreshold = 0.85

    static func preview(
        csv: String, store: WorkoutStore, assumedWeightUnit: WeightUnit? = nil
    ) -> ImportPreview? {
        guard let result = WorkoutImport.parse(csv: csv, assumedWeightUnit: assumedWeightUnit) else {
            return nil
        }
        return preview(result: result, store: store, assumedWeightUnit: assumedWeightUnit)
    }

    /// Shared by the CSV path above and `HevyAPIClient`'s network path — either way, once the
    /// import is in `ImportResult` shape, building the preview (unmatched names, set counts) is
    /// identical.
    static func preview(
        result: ImportResult, store: WorkoutStore, assumedWeightUnit: WeightUnit? = nil
    ) -> ImportPreview {
        let library = ImportExerciseLibrary(context: store.context)
        let names = Set(result.workouts.flatMap { $0.exercises.map(\.name) }).sorted()
        var unmatched: [String] = []
        var matched: [MatchedExercise] = []
        for name in names {
            guard let id = seededExerciseID(for: name, library: library)
                ?? matchedExerciseID(name, context: library.matchContext) else {
                unmatched.append(name)
                continue
            }
            let libraryName = library.model(id: id)?.name ?? name
            matched.append(MatchedExercise(sourceName: name, libraryName: libraryName))
        }
        let setsCount = result.workouts.reduce(0) { total, workout in
            total + workout.exercises.reduce(0) { $0 + $1.sets.count }
        }
        let existingKeys = existingWorkoutKeys(context: store.context)
        let alreadyImported = result.workouts.filter { existingKeys.contains(workoutKey($0)) }.count
        return ImportPreview(
            source: result.source, workouts: result.workouts, setsCount: setsCount,
            unmatchedExerciseNames: unmatched, matchedExercises: matched,
            alreadyImportedCount: alreadyImported, weightUnitAssumed: result.weightUnitAssumed,
            weightUnit: assumedWeightUnit ?? .kg, problems: result.problems
        )
    }

    /// Imports `preview.workouts` on the main actor in one go, then rebuilds the PR cache from
    /// history so records land exactly as they would have if the user had logged these sessions
    /// live. Re-running on the same file is a no-op: a workout already present (same start
    /// minute) is skipped, never duplicated. The Settings row goes through `ImportActor` instead,
    /// which drives the same `WorkoutImportWriter` off the main actor in saved batches; this
    /// one-shot form is what tests and small programmatic imports use.
    static func apply(preview: ImportPreview, store: WorkoutStore) -> WorkoutImportReport {
        let writer = WorkoutImportWriter(
            context: store.context, source: preview.source, problems: preview.problems
        )
        for imported in preview.workouts.sorted(by: { $0.startedAt < $1.startedAt }) {
            writer.insert(imported)
        }
        store.save()
        if writer.report.workoutsImported > 0 {
            // After the save, once the inverses have linked the rows — see `BackupService`.
            store.restampWorkoutTotalsAfterRemoteChange()
            store.rebuildPersonalRecords()
        }
        return writer.report
    }

    /// The Settings entry point: the same import through `ImportActor`, off the main actor in
    /// saved batches, with `progress` called as each batch lands. Ends by telling `store` about
    /// the external writes (`absorbExternalImport`) — on a cancel too, for the batches that had
    /// landed. Throws `CancellationError` when the calling task is cancelled mid-import.
    static func apply(
        preview: ImportPreview, store: WorkoutStore, progress: @escaping ImportActor.ProgressHandler
    ) async throws -> WorkoutImportReport {
        // Anything pending on the main context is saved first so the actor's context sees it.
        store.save()
        let actor = ImportActor(modelContainer: store.context.container)
        do {
            let report = try await actor.importWorkouts(preview, progress: progress)
            store.absorbExternalImport(rebuildRecords: report.workoutsImported > 0)
            return report
        } catch {
            store.absorbExternalImport(rebuildRecords: true)
            throw error
        }
    }

    // MARK: - Matching

    /// The curated alias table (`GymCore.ImportAliases`) first: an export's "Bench Press
    /// (Barbell)" or bare "Squat" names a specific seed exercise, and fuzzy matching on a
    /// 1,466-row library can't be trusted to pick it over a near-namesake.
    nonisolated static func seededExerciseID(for name: String, library: ImportExerciseLibrary) -> UUID? {
        guard let seedID = ImportAliases.seedID(for: name) else { return nil }
        return library.model(seedID: seedID)?.id
    }

    /// A match has to clear the floor *and* stand clear of the runner-up
    /// (`ExerciseMatcher.isConfident`): "Incline Bench Press" against both an incline barbell
    /// and an incline dumbbell press is a coin toss, so it's left unmatched rather than guessed.
    nonisolated static func matchedExerciseID(_ name: String, context: ParseContext) -> UUID? {
        let matches = ExerciseMatcher.match(name, in: context)
        guard let best = matches.first, best.score >= matchThreshold else { return nil }
        let runnerUp = matches.dropFirst().first?.score ?? 0
        guard ExerciseMatcher.isConfident(best: best.score, runnerUp: runnerUp) else { return nil }
        return best.id
    }

    // MARK: - Dedupe

    /// The start time, to the minute — and deliberately *not* the title.
    ///
    /// Keying on `startedAt|title` meant renaming an imported workout ("Push Day" → "Push A") and
    /// re-importing the same file inserted it a second time, because the key had moved under the
    /// store's feet. The minute (rather than the second) is what makes a CSV export and the Hevy
    /// API agree about the same session: the CSV writes "11 Mar 2024, 18:24" with no seconds while
    /// the API returns the real timestamp, so a second-precision key would import both. Two
    /// genuinely different sessions starting in the same minute is not a thing.
    nonisolated static func workoutKey(_ workout: ImportedWorkout) -> String {
        key(for: workout.startedAt)
    }

    nonisolated private static func key(for date: Date) -> String {
        String(Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down)))
    }

    nonisolated static func existingWorkoutKeys(context: ModelContext) -> Set<String> {
        let models = (try? context.fetch(FetchDescriptor<WorkoutModel>())) ?? []
        return Set(models.map { key(for: $0.startedAt) })
    }
}
