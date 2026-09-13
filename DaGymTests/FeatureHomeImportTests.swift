import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Batch B6: Home's empty-state/bodyweight tile, the weigh-in-before-workout flow, Hevy API
/// import's JSON → `ImportedWorkout` mapping, and sample-data trial mode. The Hevy client itself
/// is network-backed and untested here — only the pure mapping from its DTOs.
@MainActor
@Suite("Home, Hevy import mapping, sample data")
struct FeatureHomeImportTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(_ store: WorkoutStore, name: String) -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: "\(name) Exercise", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8)]
        )
        return store.saveRoutine(id: nil, name: name, exercises: [draft])
    }

    // MARK: - Home snapshot (item 27)

    @Test("no routines at all flags Home's starter-plan empty state")
    func hasAnyRoutinesFalseWhenNoRoutines() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        #expect(HomeSnapshot.make(store: store, preferences: preferences).hasAnyRoutines == false)
        _ = makeRoutine(store, name: "Push A")
        #expect(HomeSnapshot.make(store: store, preferences: preferences).hasAnyRoutines == true)
    }

    @Test("bodyweight delta compares the latest reading against ~30 days back")
    func bodyweightDeltaVsThirtyDaysAgo() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        let now = Date()
        let calendar = Calendar.current
        let thirtyOneDaysAgo = try #require(calendar.date(byAdding: .day, value: -31, to: now))
        store.logBodyweight(kg: 80, date: thirtyOneDaysAgo)
        store.logBodyweight(kg: 82.5, date: now)

        let snapshot = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        #expect(snapshot.bodyweightKg == 82.5)
        #expect(snapshot.bodyweightDeltaKg == 2.5)
    }

    @Test("with only one reading, there is nothing to compare and the delta is nil")
    func bodyweightDeltaNilWithOneReading() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        store.logBodyweight(kg: 80)

        let snapshot = HomeSnapshot.make(store: store, preferences: preferences)
        #expect(snapshot.bodyweightKg == 80)
        #expect(snapshot.bodyweightDeltaKg == nil)
    }

    // MARK: - Sample data trial mode (item 29)

    @Test("seeding writes eight weeks of sample-tagged workouts on the starter routines")
    func sampleDataSeeds() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        _ = makeRoutine(store, name: "Push A")
        _ = makeRoutine(store, name: "Pull B")
        _ = makeRoutine(store, name: "Legs")

        SampleDataSeeder.seed(store: store, preferences: preferences)

        #expect(preferences.sampleDataMode == true)
        let tag = SampleDataSeeder.sourceTag
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.sourceDevice == tag })
        let sampleWorkouts = (try? store.context.fetch(descriptor)) ?? []
        #expect(sampleWorkouts.count == 24)
    }

    @Test("clearing wipes every sample workout and the flag, leaving the routines")
    func sampleDataClears() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        _ = makeRoutine(store, name: "Push A")
        _ = makeRoutine(store, name: "Pull B")
        _ = makeRoutine(store, name: "Legs")
        SampleDataSeeder.seed(store: store, preferences: preferences)

        SampleDataSeeder.clear(store: store, preferences: preferences)

        #expect(preferences.sampleDataMode == false)
        #expect(store.history().isEmpty)
        #expect(store.routines().count == 3)
    }

    @Test("seeding no-ops when the starter routines aren't all present")
    func sampleDataNoOpsWithoutStarterRoutines() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        _ = makeRoutine(store, name: "Push A")

        SampleDataSeeder.seed(store: store, preferences: preferences)

        #expect(preferences.sampleDataMode == false)
        #expect(store.history().isEmpty)
    }

    // MARK: - Hevy API import mapping (item 22) — JSON fixture, no network

    private static let hevyWorkoutFixture = """
    {
        "id": "abc123",
        "title": "Push Day",
        "description": "Felt strong today",
        "start_time": "2024-05-01T10:00:00Z",
        "end_time": "2024-05-01T11:05:00Z",
        "exercises": [
            {
                "title": "Bench Press (Barbell)",
                "notes": "Paused reps",
                "sets": [
                    { "type": "warmup", "weight_kg": 40, "reps": 8 },
                    { "type": "normal", "weight_kg": 80, "reps": 5, "rpe": 8.5 },
                    { "type": "dropset", "weight_kg": 60, "reps": 8 },
                    { "type": "failure", "weight_kg": 80, "reps": 3 }
                ]
            },
            {
                "title": "Plank",
                "notes": "",
                "sets": [
                    { "type": "normal", "duration_seconds": 60 }
                ]
            }
        ]
    }
    """

    private static let hevyResponseFixture = """
    { "page": 1, "page_count": 1, "workouts": [\(hevyWorkoutFixture)] }
    """

    private func decodeHevyWorkout(_ json: String) throws -> HevyWorkout {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let container = try valueDecoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = HevyDateFormat.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(text)")
            }
            return date
        }
        return try decoder.decode(HevyWorkout.self, from: Data(json.utf8))
    }

    @Test("a Hevy workout's set types map to the right SetKind, weight and reps")
    func mapsHevyWorkoutToImportedWorkout() throws {
        let workout = try decodeHevyWorkout(Self.hevyWorkoutFixture)
        let imported = HevyAPIClient.map(workout)

        #expect(imported.title == "Push Day")
        #expect(imported.notes == "Felt strong today")
        #expect(imported.exercises.count == 2)

        let bench = try #require(imported.exercises.first)
        #expect(bench.name == "Bench Press (Barbell)")
        #expect(bench.note == "Paused reps")
        #expect(bench.sets.map(\.kind) == [.warmup, .working, .drop, .failure])
        #expect(bench.sets[1].weightKg == 80)
        #expect(bench.sets[1].reps == 5)
        #expect(bench.sets[1].rpe == 8.5)

        let plank = imported.exercises[1]
        #expect(plank.sets.first?.durationSeconds == 60)
    }

    @Test("an unrecognized set type falls back to a working set")
    func unrecognizedSetTypeFallsBackToWorking() throws {
        let json = """
        {
            "id": "x", "title": "T", "start_time": "2024-05-01T10:00:00Z",
            "exercises": [
                { "title": "Squat", "sets": [ { "type": "amrap", "weight_kg": 100, "reps": 5 } ] }
            ]
        }
        """
        let workout = try decodeHevyWorkout(json)
        let imported = HevyAPIClient.map(workout)
        #expect(imported.exercises.first?.sets.first?.kind == .working)
    }

    @Test("the paged-response envelope decodes and wraps the same workout shape")
    func decodesPagedResponseEnvelope() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let container = try valueDecoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = HevyDateFormat.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(text)")
            }
            return date
        }
        let response = try decoder.decode(
            HevyWorkoutsResponse.self, from: Data(Self.hevyResponseFixture.utf8)
        )
        #expect(response.page == 1)
        #expect(response.pageCount == 1)
        #expect(response.workouts.count == 1)
        #expect(response.workouts[0].title == "Push Day")
    }
}
