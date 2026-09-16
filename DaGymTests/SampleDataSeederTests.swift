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

    /// `RoutineSeeder.seedStarters` counts a renamed starter as present (by its starter id), so
    /// the seeder must find it the same way — matching by name only made "Explore with sample
    /// data" a silent no-op for a lifter who had renamed one of the trio.
    @Test("a renamed starter still gets the sample history, matched by its starter id")
    func renamedStarterStillSeeds() throws {
        let store = try makeStore(seed: .firstLaunch)
        let preferences = Preferences(suite: makeSuite(#function))
        RoutineSeeder.seedStarters(RoutineSeeder.pushPullLegsNames, store: store)
        let pushID = try #require(store.routines().first { $0.name == "Push A" }?.id)
        let drafts = try #require(store.routineDrafts(id: pushID)?.drafts)
        store.saveRoutine(id: pushID, name: "Push Day", exercises: drafts)

        SampleDataSeeder.seed(store: store, preferences: preferences)

        #expect(preferences.sampleDataMode)
        #expect(store.routines().count == 3)
        let workouts = store.finishedWorkoutModelsNewestFirst()
        #expect(workouts.count == 24)
        #expect(workouts.filter { $0.routineID == pushID }.count == 8)
    }

    @Test("the onboarding row says it is building while the seed runs")
    func welcomeRowShowsBusyState() {
        #expect(OnboardingWelcomeStep.sampleDataTitle(isSeeding: false) == "Explore with sample data")
        #expect(OnboardingWelcomeStep.sampleDataTitle(isSeeding: true) == "Building sample data…")
    }
}
