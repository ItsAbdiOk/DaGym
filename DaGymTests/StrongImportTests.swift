import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// End-to-end cover for the Strong CSV path: a real-shaped export (quoted fields, a `Weight Unit`
/// column, free-text durations, a timed hold, an exercise we've never heard of) has to land as
/// history against the seeded library, matching the common names rather than inventing duplicates.
@MainActor
@Suite("Strong CSV import")
struct StrongImportTests {
    private static let header = """
    "Date","Workout Name","Duration","Exercise Name","Set Order","Weight","Weight Unit","Reps",\
    "RPE","Distance","Distance Unit","Seconds","Notes"
    """

    private static let export = """
    \(header)
    "2026-08-03 18:12:00","Push A","1h 4min","Bench Press (Barbell)","1","60","kg","10","","0","km","0",""
    "2026-08-03 18:12:00","Push A","1h 4min","Bench Press (Barbell)","2","80","kg","8","8","0","km","0",""
    "2026-08-03 18:12:00","Push A","1h 4min","Triceps Pushdown","1","35","kg","15","","0","km","0",""
    "2026-08-05 18:30:00","Legs","58min","Squat (Barbell)","1","90","kg","5","8","0","km","0",""
    "2026-08-05 18:30:00","Legs","58min","Pull Up","1","0","kg","8","","0","km","0",""
    "2026-08-05 18:30:00","Legs","58min","Plank","1","0","kg","0","","0","km","60",""
    "2026-08-05 18:30:00","Legs","58min","Some Invented Machine","1","40","kg","12","","0","km","0",""
    """

    private static let poundsExport = """
    \(header)
    "2026-08-10 19:00:00","Push","45min","Bench Press (Barbell)","1","185","lbs","5","8","0","mi","0",""
    """

    @Test("common Strong names resolve to seeded exercises; only a genuine unknown is invented")
    func matchesSeededLibrary() throws {
        let store = try makeStore(seed: .exercises)
        let preview = try #require(WorkoutImportService.preview(csv: Self.export, store: store))
        #expect(preview.source == .strong)
        #expect(preview.workouts.count == 2)
        #expect(preview.setsCount == 7)
        #expect(preview.unmatchedExerciseNames == ["Some Invented Machine"])
        #expect(preview.problems.isEmpty)

        let report = WorkoutImportService.apply(preview: preview, store: store)
        #expect(report.workoutsImported == 2)
        #expect(report.setsImported == 7)
        #expect(report.exercisesCreated == 1)
        #expect(store.history().count == 2)
    }

    @Test("a workout's numbers, duration and timed hold survive the round trip")
    func keepsNumbersAndDuration() throws {
        let store = try makeStore(seed: .exercises)
        let preview = try #require(WorkoutImportService.preview(csv: Self.export, store: store))
        _ = WorkoutImportService.apply(preview: preview, store: store)

        let legs = try #require(store.history().first { $0.title == "Legs" })
        let detail = store.workoutDetail(id: legs.id)
        #expect(detail.exercises.count == 4)
        let squat = try #require(detail.exercises.first { $0.exercise.name.contains("Squat") })
        #expect(squat.sets.first?.weightKg == 90)
        #expect(squat.sets.first?.reps == 5)
        let plank = try #require(detail.exercises.first { $0.exercise.name == "Plank" })
        #expect(plank.sets.first?.durationSeconds == 60)

        let push = try #require(store.history().first { $0.title == "Push A" })
        let pushDetail = store.workoutDetail(id: push.id)
        // "1h 4min" in the Duration column, not a wall-clock guess.
        let ended = try #require(pushDetail.endedAt)
        #expect(ended.timeIntervalSince(pushDetail.startedAt) == 64 * 60)
    }

    @Test("a pounds export is stored in kilograms")
    func convertsPounds() throws {
        let store = try makeStore(seed: .exercises)
        let preview = try #require(WorkoutImportService.preview(csv: Self.poundsExport, store: store))
        _ = WorkoutImportService.apply(preview: preview, store: store)
        let workout = try #require(store.history().first)
        let detail = store.workoutDetail(id: workout.id)
        let weight = try #require(detail.exercises.first?.sets.first?.weightKg)
        #expect(abs(weight - 83.91) < 0.05)
    }

    @Test("re-importing the same file adds nothing")
    func reimportIsANoOp() throws {
        let store = try makeStore(seed: .exercises)
        let first = try #require(WorkoutImportService.preview(csv: Self.export, store: store))
        _ = WorkoutImportService.apply(preview: first, store: store)
        let second = try #require(WorkoutImportService.preview(csv: Self.export, store: store))
        let report = WorkoutImportService.apply(preview: second, store: store)
        #expect(report.workoutsImported == 0)
        #expect(report.workoutsSkipped == 2)
        #expect(store.history().count == 2)
    }
}
