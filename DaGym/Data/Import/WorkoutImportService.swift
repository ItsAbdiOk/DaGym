import Foundation
import GymCore
import SwiftData

/// What a parsed CSV would add, shown by `ImportSettingsSection` before the user confirms
/// (plan.md §6.8: "show a preview + problems before confirming").
struct ImportPreview {
    var source: ImportSource
    var workouts: [ImportedWorkout]
    var setsCount: Int
    /// Exercise names in the file that don't confidently match anything in the library — these
    /// become custom exercises on `apply`.
    var unmatchedExerciseNames: [String]
    var problems: [ImportProblem]
}

/// Counts from `WorkoutImportService.apply`, named distinctly from `Data/Backup`'s
/// `ImportReport` (same module, different feature) so the two never collide.
struct WorkoutImportReport: Equatable {
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
    static let matchThreshold = 0.85

    static func preview(csv: String, store: WorkoutStore) -> ImportPreview? {
        guard let result = WorkoutImport.parse(csv: csv) else { return nil }
        let context = matchContext(store: store)
        let names = Set(result.workouts.flatMap { $0.exercises.map(\.name) })
        let unmatched = names.filter { matchedExerciseID($0, context: context) == nil }.sorted()
        let setsCount = result.workouts.reduce(0) { total, workout in
            total + workout.exercises.reduce(0) { $0 + $1.sets.count }
        }
        return ImportPreview(
            source: result.source, workouts: result.workouts, setsCount: setsCount,
            unmatchedExerciseNames: unmatched, problems: result.problems
        )
    }

    /// Imports `preview.workouts`, oldest first so the PR cache builds up exactly as it would
    /// have if the user had logged these sessions live. Re-running on the same file is a no-op:
    /// a workout already present (same `startedAt` + `title`) is skipped, never duplicated.
    static func apply(preview: ImportPreview, store: WorkoutStore) -> WorkoutImportReport {
        var report = WorkoutImportReport()
        report.problems = preview.problems.map { "Line \($0.line): \($0.message)" }
        var exerciseCache: [String: UUID] = [:]
        let environment = ImportEnvironment(
            store: store, context: matchContext(store: store), source: preview.source
        )
        let existingKeys = existingWorkoutKeys(store: store)
        var latestDateSoFar = latestFinishedWorkoutDate(store: store)

        for imported in preview.workouts.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard !existingKeys.contains(workoutKey(imported)) else {
                report.workoutsSkipped += 1
                continue
            }
            _ = insertWorkout(
                imported, environment: environment, exerciseCache: &exerciseCache,
                latestDateSoFar: latestDateSoFar, report: &report
            )
            latestDateSoFar = max(latestDateSoFar ?? imported.startedAt, imported.startedAt)
            report.workoutsImported += 1
        }
        store.save()
        return report
    }

    // MARK: - Matching

    private static func matchContext(store: WorkoutStore) -> ParseContext {
        let candidates = store.exercises(matching: "").map {
            ParseContext.ExerciseCandidate(id: $0.id, name: $0.name, equipment: $0.equipment)
        }
        return ParseContext(unit: .kg, library: candidates)
    }

    private static func matchedExerciseID(_ name: String, context: ParseContext) -> UUID? {
        let matches = ExerciseMatcher.match(name, in: context)
        guard let best = matches.first, best.score >= matchThreshold else { return nil }
        return best.id
    }

    /// Resolves `name` to an exercise id, creating a custom exercise the first time an import
    /// batch sees an unmatched name (subsequent rows with the same name reuse it).
    static func resolveExercise(
        _ name: String, store: WorkoutStore, context: ParseContext,
        exerciseCache: inout [String: UUID], report: inout WorkoutImportReport
    ) -> UUID {
        let key = name.lowercased()
        if let cached = exerciseCache[key] { return cached }
        if let matched = matchedExerciseID(name, context: context) {
            exerciseCache[key] = matched
            return matched
        }
        let created = store.createCustomExercise(
            name: name, primary: [], equipment: "other", style: .weightReps
        )
        exerciseCache[key] = created.id
        report.exercisesCreated += 1
        return created.id
    }

    // MARK: - Dedupe

    private static func workoutKey(_ workout: ImportedWorkout) -> String {
        "\(workout.startedAt.timeIntervalSinceReferenceDate)|\(workout.title)"
    }

    private static func existingWorkoutKeys(store: WorkoutStore) -> Set<String> {
        let models = (try? store.context.fetch(FetchDescriptor<WorkoutModel>())) ?? []
        return Set(models.map { "\($0.startedAt.timeIntervalSinceReferenceDate)|\($0.title)" })
    }

    private static func latestFinishedWorkoutDate(store: WorkoutStore) -> Date? {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        var descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? store.context.fetch(descriptor))?.first?.startedAt
    }
}
