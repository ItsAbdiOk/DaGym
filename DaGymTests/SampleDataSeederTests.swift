import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The shape of the sample history `SampleDataSeeder` writes — what the App Store screenshots
/// (`-dgScreenshots`) and the onboarding trial both show.
@MainActor
@Suite("Sample data seeder")
struct SampleDataSeederTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    @Test("loads start at a trained lifter's numbers, not the bare increment")
    func startingWeightsByEquipment() {
        let bench = ExerciseInfo(name: "Bench", primary: [.chest], equipment: "Barbell", incrementKg: 2.5)
        let squat = ExerciseInfo(name: "Squat", primary: [.quads], equipment: "Barbell", incrementKg: 5)
        let pullup = ExerciseInfo(
            name: "Pull-up", primary: [.lats], equipment: "Bodyweight", incrementKg: 0,
            loggingStyle: .bodyweightReps
        )
        #expect(SampleDataSeeder.startingWeightKg(for: bench) == 80)
        #expect(SampleDataSeeder.startingWeightKg(for: squat) == 80)
        #expect(SampleDataSeeder.startingWeightKg(for: pullup) == 0)
    }

    @Test("seeded sets follow the routine's own plan: set count, rep target, an RPE, a recent session")
    func seededSetsFollowThePlan() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        for name in ["Push A", "Pull B", "Legs"] {
            let exercise = store.createCustomExercise(
                name: "\(name) Exercise", primary: [.chest], equipment: "Barbell", style: .weightReps
            )
            let sets = (0..<4).map { _ in
                PlannedSetDraft(kind: .working, targetReps: 10, targetRepsHigh: 12)
            }
            let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: sets)
            _ = store.saveRoutine(id: nil, name: name, exercises: [draft])
        }
        let now = Date()

        SampleDataSeeder.seed(store: store, preferences: preferences, now: now)

        let workouts = store.finishedWorkoutModelsNewestFirst()
        #expect(workouts.count == 24)
        let newest = try #require(workouts.first)
        let sets = try #require(newest.exercises?.first?.sets)
        #expect(sets.count == 4)
        #expect(sets.allSatisfy { $0.reps == 12 || $0.reps == 11 })
        #expect(sets.allSatisfy { $0.rpe != nil })
        #expect(sets.allSatisfy { $0.weightKg >= 80 })
        // Newest session is yesterday, so "this week" and the recovery map have something recent.
        let daysAgo = Calendar.current.dateComponents([.day], from: newest.startedAt, to: now).day
        #expect(daysAgo == 1)
    }
}
