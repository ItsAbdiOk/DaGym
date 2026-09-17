import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The backup round trip — export → import on a fresh store → every screen identical; the same
/// file twice; a file naming an exercise that doesn't exist — and the import history log every
/// import path writes.
@MainActor
@Suite("Edge data: backup and import history", .serialized)
struct EdgeDataBackupTests {

    private func preferences(unit: WeightUnit = .kg) -> Preferences {
        let preferences = Preferences(suite: UserDefaults(suiteName: "edge-bk-\(UUID())") ?? .standard)
        preferences.weightUnit = unit
        preferences.distanceUnit = DistanceUnit.matching(unit)
        return preferences
    }

    // MARK: - 10. Backup round trip

    @Test("export → import on a fresh store gives every screen the same numbers; twice adds nothing")
    func backupRoundTripMatchesEveryScreen() async throws {
        let builder = try CoachEvalStoreBuilder()
        var story = DemoLifter(builder: builder)
        try story.build()
        builder.finish()
        let source = builder.store
        let now = builder.now
        let preferences = preferences(unit: .lb)
        preferences.weekStartsMonday = false
        preferences.weeklyGoal = 5
        let document = try BackupCodec.decode(BackupCodec.encode(
            BackupService.export(context: source.context, preferences: preferences)
        ))

        let fresh = try makeStore(seed: .firstLaunch)
        let restoredPreferences = self.preferences()
        let log = ImportHistoryLog.scratch()
        let report = try await BackupService.import(
            document: document, store: fresh, preferences: restoredPreferences, history: log
        )
        #expect(report.problems.isEmpty, Comment(rawValue: report.problems.joined(separator: " | ")))
        #expect(restoredPreferences.weightUnit == .lb && restoredPreferences.weeklyGoal == 5)
        #expect(!restoredPreferences.weekStartsMonday)

        let before = screenNumbers(store: source, preferences: preferences, now: now)
        let after = screenNumbers(store: fresh, preferences: restoredPreferences, now: now)
        #expect(before == after)

        let again = try await BackupService.import(
            document: document, store: fresh, preferences: restoredPreferences, history: log
        )
        #expect(again.workoutsImported == 0 && again.routinesImported == 0)
        #expect(again.bodyMeasurementsImported == 0)
        #expect(screenNumbers(store: fresh, preferences: restoredPreferences, now: now) == after)
        let entries = log.entries()
        #expect(entries.count == 2)
        #expect(entries.first?.summary == "\(document.workouts.count) skipped workouts")
        #expect(entries.last?.summary.hasPrefix("\(document.workouts.count) workouts") == true)
    }

    @Test("a backup whose routine names a missing exercise imports the rest and says what it skipped")
    func backupWithMissingExercise() async throws {
        let store = try makeStore(seed: .exercises)
        let bench = try #require(store.exercises(matching: CoachEvalLift.bench).first)
        _ = store.saveRoutine(id: nil, name: "Push", exercises: [
            RoutineExerciseDraft(exerciseID: bench.id, sets: [PlannedSetDraft(kind: .working, targetReps: 5)])
        ])
        var document = BackupService.export(context: store.context)
        #expect(document.routines.count == 1)
        document.routines[0].exercises.append(BackupRoutineExercise(
            order: 1, exerciseSeedID: "not-a-real-seed", exerciseName: "Ghost Press", supersetGroup: nil,
            restOverrideSeconds: nil, note: "", plannedSets: []
        ))

        let fresh = try makeStore(seed: .firstLaunch)
        let log = ImportHistoryLog.scratch()
        let report = try await BackupService.import(
            document: document, store: fresh, preferences: preferences(), history: log
        )
        #expect(report.routinesImported == 1)
        #expect(report.problems.count == 1)
        #expect(report.problems.first?.contains("Ghost Press") == true)
        #expect(fresh.routines().first?.exercises.count == 1)
        #expect(log.entries().first?.problems == 1)
        let preferences = preferences()
        _ = HomeSnapshot.make(store: fresh, preferences: preferences)
        _ = ProgressHubSummary.make(store: fresh, preferences: preferences)
    }

    // MARK: - 11. Import history

    @Test("every import path writes one entry; the log survives a reload and caps at capacity")
    func importHistoryLog() async throws {
        let log = ImportHistoryLog.scratch()
        #expect(log.entries().isEmpty)

        let store = try makeStore(seed: .exercises)
        let csv = """
        "Date","Workout Name","Duration","Exercise Name","Set Order","Weight","Weight Unit","Reps",\
        "RPE","Distance","Distance Unit","Seconds","Notes"
        "2026-08-03 18:12:00","Push A","1h 4min","Bench Press (Barbell)","1","60","kg","10","","0","km","0",""
        "2026-08-03 18:12:00","Push A","1h 4min","Bench Press (Barbell)","2","80","kg","8","8","0","km","0",""
        """
        let preview = try #require(WorkoutImportService.preview(csv: csv, store: store))
        let report = try await WorkoutImportService.apply(
            preview: preview, store: store, progress: { _ in }, history: log
        )
        #expect(report.workoutsImported == 1)
        let strong = try #require(log.entries().first)
        #expect(strong.source == "Strong")
        #expect(strong.summary == "1 workout, 2 sets")

        let health = ImportHistoryEntry.health(workouts: 0)
        log.record(health)
        #expect(log.entries().first?.summary == "Nothing new")
        #expect(log.entries().first?.source == "Apple Health")

        let reloaded = ImportHistoryLog(fileURL: log.fileURL)
        #expect(reloaded.entries().map(\.id) == log.entries().map(\.id))
        let reloadedDate = try #require(reloaded.entries().first?.date)
        #expect(abs(reloadedDate.timeIntervalSince(health.date)) < 1, "ISO 8601 keeps whole seconds")

        for index in 0..<ImportHistoryLog.capacity {
            log.record(.health(workouts: index, date: Date().addingTimeInterval(Double(index))))
        }
        #expect(log.entries().count == ImportHistoryLog.capacity)
        #expect(log.entries().first?.counts.first?.value == ImportHistoryLog.capacity - 1)
        log.clear()
        #expect(log.entries().isEmpty)
        #expect(ImportHistoryLog(fileURL: log.fileURL).entries().isEmpty)
    }

    // MARK: - Helpers

    /// The numbers every screen prints, as one comparable value.
    private struct ScreenNumbers: Equatable {
        var thisWeek: Int
        var streak: Int
        var longest: Int
        var volume: Int
        var lastWeekVolume: Int
        var lifetimeWorkouts: Int
        var lifetimeVolume: Int
        var records: Int
        var tracked: Int
        var headline: [String]
        var topMuscle: Muscle?
        var bodyweight: Double?
        var routines: [String]
        var scheduleDays: Int
        var recovery: [Muscle: Int]
        var achievements: Int
        var notes: Int
        var upNext: String?
    }

    private func screenNumbers(store: WorkoutStore, preferences: Preferences, now: Date) -> ScreenNumbers {
        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        let you = YouSummary.make(store: store, preferences: preferences, now: now)
        let hub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        let stats = store.lifetimeStats()
        let bench = store.exercises(matching: CoachEvalLift.bench).first
        return ScreenNumbers(
            thisWeek: home.thisWeekCount, streak: home.streakCurrent, longest: home.streakLongest,
            volume: Int(hub.volumeKg.rounded()), lastWeekVolume: Int(hub.lastWeekVolumeKg.rounded()),
            lifetimeWorkouts: stats.workouts, lifetimeVolume: Int(stats.volumeKg.rounded()),
            records: store.personalRecords().flatMap(\.records).count, tracked: hub.trackedExercises,
            headline: hub.headlineLifts.map { "\($0.name) \(Int($0.e1rmKg.rounded()))" },
            topMuscle: hub.topMuscle?.muscle, bodyweight: home.bodyweightKg,
            routines: store.routines().map(\.name).sorted(), scheduleDays: store.schedule().dayRoutines.count,
            recovery: home.recoveryMap.mapValues { Int(($0 * 100).rounded()) },
            achievements: store.achievements().count,
            notes: bench.map { store.exerciseNotes(exerciseID: $0.id).count } ?? -1,
            upNext: you.upNext.map { "\($0.routineName) \($0.weekday) \($0.exerciseCount)" }
        )
    }
}
