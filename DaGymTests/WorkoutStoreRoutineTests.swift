import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore routines")
struct WorkoutStoreRoutineTests {
    @Test("routine save/load round trip including superset groups and planned set kinds")
    func routineRoundTrip() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let flye = store.createCustomExercise(
            name: "Cable Fly", primary: [.chest], equipment: "Cable", style: .weightReps
        )

        let benchDraft = RoutineExerciseDraft(
            exerciseID: bench.id, supersetGroup: 1,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .amrap, targetReps: 8, targetWeightKg: 80)
            ]
        )
        let flyeDraft = RoutineExerciseDraft(
            exerciseID: flye.id, supersetGroup: 1,
            sets: [PlannedSetDraft(kind: .drop, targetReps: 12, targetWeightKg: 20)]
        )

        let saved = store.saveRoutine(
            id: nil, name: "Push A", progressionRule: "linear", exercises: [benchDraft, flyeDraft]
        )

        let loaded = store.routines().first { $0.id == saved.id }
        #expect(loaded?.exercises.map(\.name) == ["Bench Press", "Cable Fly"])
        #expect(loaded?.setCount == 3)

        let routineModel = store.fetchRoutineModel(id: saved.id)
        let routineExercises = (routineModel?.exercises ?? []).sorted { $0.order < $1.order }
        #expect(routineExercises.map(\.supersetGroup) == [1, 1])

        let benchSets = (routineExercises.first?.plannedSets ?? []).sorted { $0.order < $1.order }
        #expect(benchSets.map(\.setKind) == [.warmup, .amrap])
    }
}
