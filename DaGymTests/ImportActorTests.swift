import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// `ImportActor` — the off-main, batched writer behind the Settings import rows — has to land
/// exactly what the one-shot main-actor path lands: same counts, same totals, same dedupe, and a
/// store the main-actor `WorkoutStore` knows about afterwards (stamped totals, PR cache, catalogue).
@MainActor
@Suite("Import actor")
struct ImportActorTests {
    private static let header = """
    "Date","Workout Name","Duration","Exercise Name","Set Order","Weight","Weight Unit","Reps",\
    "RPE","Distance","Distance Unit","Seconds","Notes"
    """

    /// Ten set rows per workout — 5 × bench 60 kg × 10, 4 × squat 100 kg × 5, one row on a name
    /// the library has never heard of — so `workouts × 10` rows, one workout per day.
    static func strongExport(workouts: Int) -> String {
        var lines = [header]
        let start = Date(timeIntervalSince1970: 1_577_901_600) // 2020-01-01 18:00 UTC
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for day in 0..<workouts {
            let date = formatter.string(from: start.addingTimeInterval(Double(day) * 86_400))
            for set in 1...5 {
                lines.append(row(date, "Bench Press (Barbell)", set, weight: 60, reps: 10))
            }
            for set in 1...4 {
                lines.append(row(date, "Squat (Barbell)", set, weight: 100, reps: 5))
            }
            lines.append(row(date, "Some Invented Machine", 1, weight: 40, reps: 12))
        }
        return lines.joined(separator: "\n")
    }

    /// Σ load × reps over the ten rows above.
    static let volumePerWorkout = 5 * 60.0 * 10 + 4 * 100.0 * 5 + 40.0 * 12

    private static func row(_ date: String, _ name: String, _ order: Int, weight: Int, reps: Int) -> String {
        let head = "\"\(date)\",\"Day\",\"1h\",\"\(name)\",\"\(order)\""
        return head + ",\"\(weight)\",\"kg\",\"\(reps)\",\"\",\"0\",\"km\",\"0\",\"\""
    }

    private func seededStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        return WorkoutStore(context: context)
    }

    private func finishedWorkouts(_ store: WorkoutStore) throws -> [WorkoutModel] {
        try store.context.fetch(FetchDescriptor<WorkoutModel>())
    }

    // MARK: - CSV

    @Test("a 3,000-row Strong export lands with the right counts and stamped totals, and never twice")
    func importsThreeThousandRows() async throws {
        let store = try seededStore()
        let csv = Self.strongExport(workouts: 300)
        let preview = try #require(WorkoutImportService.preview(csv: csv, store: store))
        #expect(preview.setsCount == 3000)

        let updates = ProgressLog()
        let report = try await WorkoutImportService.apply(preview: preview, store: store) {
            updates.append($0)
        }
        #expect(report.workoutsImported == 300)
        #expect(report.setsImported == 3000)
        #expect(report.exercisesCreated == 1)
        #expect(report.workoutsSkipped == 0)
        #expect(updates.last == ImportProgress(done: 300, total: 300))
        #expect(updates.count > 1, "progress is reported per batch, not once at the end")

        let workouts = try finishedWorkouts(store)
        #expect(workouts.count == 300)
        #expect(workouts.allSatisfy { $0.setsDone == 10 && $0.volumeKg == Self.volumePerWorkout })
        #expect(store.history().count == 300)
        #expect(try store.context.fetchCount(FetchDescriptor<PersonalRecordModel>()) > 0)
        // The main-actor store's catalogue sees the custom exercise the actor created.
        #expect(store.exerciseCatalogue().models.contains { $0.name == "Some Invented Machine" })

        let second = try #require(WorkoutImportService.preview(csv: csv, store: store))
        #expect(second.alreadyImportedCount == 300)
        let secondReport = try await WorkoutImportService.apply(preview: second, store: store) { _ in }
        #expect(secondReport.workoutsImported == 0)
        #expect(secondReport.workoutsSkipped == 300)
        #expect(secondReport.exercisesCreated == 0)
        #expect(try finishedWorkouts(store).count == 300)
    }

    @Test("cancelling mid-way keeps whole committed batches, leaves the store consistent and resumes")
    func cancellationLeavesConsistentStore() async throws {
        let store = try seededStore()
        let csv = Self.strongExport(workouts: 300)
        let preview = try #require(WorkoutImportService.preview(csv: csv, store: store))

        let handle = TaskHandle()
        let task = Task { @MainActor in
            try await WorkoutImportService.apply(preview: preview, store: store) { _ in
                // Cancel from the first batch's progress callback: the next commit still lands
                // its batch, then throws.
                handle.cancel()
            }
        }
        handle.task = task
        await #expect(throws: CancellationError.self) { try await task.value }

        let workouts = try finishedWorkouts(store)
        #expect(!workouts.isEmpty)
        #expect(workouts.count < 300)
        // Whole workouts only, every one stamped, and the PR cache already knows them.
        #expect(workouts.allSatisfy { $0.setsDone == 10 && $0.volumeKg == Self.volumePerWorkout })
        #expect(try store.context.fetchCount(FetchDescriptor<PersonalRecordModel>()) > 0)
        #expect(store.history().count == workouts.count)

        let resumed = try #require(WorkoutImportService.preview(csv: csv, store: store))
        #expect(resumed.alreadyImportedCount == workouts.count)
        let report = try await WorkoutImportService.apply(preview: resumed, store: store) { _ in }
        #expect(report.workoutsImported == 300 - workouts.count)
        #expect(try finishedWorkouts(store).count == 300)
    }

    // MARK: - Backup

    @Test("a backup restore through the actor equals the one-shot main-actor restore")
    func restoreMatchesSyncImport() async throws {
        let source = try seededStore()
        let preview = try #require(
            WorkoutImportService.preview(csv: Self.strongExport(workouts: 40), store: source)
        )
        _ = WorkoutImportService.apply(preview: preview, store: source)
        let benchID = try #require(source.exerciseID(seedID: "Barbell_Bench_Press_-_Medium_Grip"))
        source.toggleFavorite(id: benchID)
        _ = source.saveRoutine(
            id: nil, name: "Push A",
            exercises: [RoutineExerciseDraft(exerciseID: benchID, sets: [PlannedSetDraft(targetReps: 8)])]
        )
        let document = BackupService.export(context: source.context)

        let sync = try seededStore()
        let syncReport = BackupService.import(document: document, context: sync.context, store: sync)

        let actor = try seededStore()
        // Registered in the main context before the restore, so the favourite the actor writes
        // has to reach an object this context already holds — not just a fresh fetch.
        let actorBenchID = try #require(actor.exerciseID(seedID: "Barbell_Bench_Press_-_Medium_Grip"))
        let benchBefore = try #require(actor.fetchExerciseModel(id: actorBenchID))
        #expect(!benchBefore.isFavorite)
        let updates = ProgressLog()
        let actorReport = try await BackupService.import(
            document: document, store: actor, preferences: Preferences()
        ) { updates.append($0) }

        #expect(actorReport.workoutsImported == syncReport.workoutsImported)
        #expect(actorReport.workoutsImported == 40)
        #expect(actorReport.routinesImported == syncReport.routinesImported)
        #expect(actorReport.exercisesImported == syncReport.exercisesImported)
        #expect(actorReport.problems == syncReport.problems)
        #expect(actorReport.preferencesRestored == syncReport.preferencesRestored)
        #expect(updates.last?.done == updates.last?.total)

        let syncWorkouts = try finishedWorkouts(sync)
        let actorWorkouts = try finishedWorkouts(actor)
        #expect(actorWorkouts.count == syncWorkouts.count)
        #expect(actorWorkouts.map(\.volumeKg).reduce(0, +) == syncWorkouts.map(\.volumeKg).reduce(0, +))
        #expect(actorWorkouts.map(\.setsDone).reduce(0, +) == syncWorkouts.map(\.setsDone).reduce(0, +))
        #expect(
            try actor.context.fetchCount(FetchDescriptor<PersonalRecordModel>())
                == sync.context.fetchCount(FetchDescriptor<PersonalRecordModel>())
        )
        #expect(actor.history().count == 40)
        #expect(try #require(actor.fetchExerciseModel(id: actorBenchID)).isFavorite)
        #expect(actor.exerciseCatalogue().models.contains { $0.name == "Some Invented Machine" })

        // Same file again: nothing duplicated either way.
        let again = try await BackupService.import(
            document: document, store: actor, preferences: Preferences()
        )
        #expect(again.workoutsImported == 0)
        #expect(again.workoutsSkipped == 40)
        #expect(try finishedWorkouts(actor).count == 40)
    }
}

/// Progress updates as the actor reported them; appended from the actor's executor, read on
/// the main actor once the import has returned.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [ImportProgress] = []

    func append(_ progress: ImportProgress) {
        lock.withLock { updates.append(progress) }
    }

    var count: Int { lock.withLock { updates.count } }
    var last: ImportProgress? { lock.withLock { updates.last } }
}

/// Lets the progress callback cancel the task that is running the import.
private final class TaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Task<WorkoutImportReport, any Error>?

    var task: Task<WorkoutImportReport, any Error>? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func cancel() { task?.cancel() }
}
