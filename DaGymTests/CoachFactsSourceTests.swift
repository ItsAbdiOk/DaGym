import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Each question tool writes out the store's numbers in full — these pin the exact sentences,
/// the week clamping, and the "nothing to say" fallbacks the model may quote.
@MainActor
@Suite("Coach facts source")
struct CoachFactsSourceTests {
    private func makeStore() throws -> WorkoutStore {
        WorkoutStore(context: ModelContext(try ModelContainer.dagym(inMemory: true)))
    }

    private func benchRoutine(_ store: WorkoutStore) -> (bench: ExerciseInfo, routine: RoutineInfo) {
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let sets = (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60) }
        let routine = store.saveRoutine(
            id: nil, name: "Push", exercises: [RoutineExerciseDraft(exerciseID: bench.id, sets: sets)]
        )
        return (bench, routine)
    }

    /// Finishes one session with every planned bench set done at 80 kg × 8.
    private func logSession(_ store: WorkoutStore, routine: RoutineInfo) {
        let session = store.startWorkout(routineID: routine.id)
        for index in session.exercises[0].sets.indices {
            session.exercises[0].sets[index].weightKg = 80
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)
    }

    @Test("weekly volume counts the working sets and averages them per week")
    func weeklyVolume() throws {
        let store = try makeStore()
        let (_, routine) = benchRoutine(store)
        logSession(store, routine: routine)
        let source = CoachFactsSource(store: store, unit: .kg)
        let text = source.answerCoachQuery(.weeklyVolume(muscle: "chest", weeks: 2)).text
        #expect(text == "Chest: 3 working sets over the last 2 weeks, about 1.5 sets a week.")
    }

    @Test("weeks are clamped to 1…12 before they reach the store")
    func weeklyVolumeClampsWeeks() throws {
        let store = try makeStore()
        let source = CoachFactsSource(store: store, unit: .kg)
        #expect(source.answerCoachQuery(.weeklyVolume(muscle: "Quads", weeks: 0)).text
            == "Quads: 0 working sets over the last 1 weeks, about 0 sets a week.")
        let capped = source.answerCoachQuery(.weeklyVolume(muscle: "quads", weeks: 99)).text
        #expect(capped.contains("last 12 weeks"))
        #expect(source.answerCoachQuery(.adherence(weeks: -3)).text
            == "No sessions were planned in the last 1 weeks.")
    }

    @Test("a muscle the library doesn't know is answered, not guessed")
    func unknownMuscle() throws {
        let source = CoachFactsSource(store: try makeStore(), unit: .kg)
        #expect(source.answerCoachQuery(.weeklyVolume(muscle: "Wings", weeks: 4)).text
            == "No muscle called Wings.")
        #expect(source.answerCoachQuery(.recovery(muscle: "Wings")).text == "No muscle called Wings.")
    }

    @Test("personal records: none yet, then each record kind on its own line in the lifter's unit")
    func personalRecords() throws {
        let store = try makeStore()
        let (_, routine) = benchRoutine(store)
        let source = CoachFactsSource(store: store, unit: .lb)
        #expect(source.answerCoachQuery(.personalRecords(exercise: "bench press")).text
            == "No personal records on Bench Press yet.")
        logSession(store, routine: routine)
        let text = source.answerCoachQuery(.personalRecords(exercise: "Bench Press")).text
        #expect(text.hasPrefix("Bench Press records — "))
        #expect(text.contains("Heaviest weight: "))
        #expect(text.contains("lb"))
        #expect(!text.contains("kg"))
        #expect(source.answerCoachQuery(.personalRecords(exercise: "Nope")).text
            == "No exercise called Nope in the library.")
    }

    @Test("adherence reports kept-of-planned and a rounded percent over the trailing window")
    func adherence() throws {
        let store = try makeStore()
        let (_, routine) = benchRoutine(store)
        let everyDay = Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, routine.id) })
        store.saveSchedule(WeeklySchedule(days: everyDay))
        logSession(store, routine: routine)
        let source = CoachFactsSource(store: store, unit: .kg)
        #expect(source.answerCoachQuery(.adherence(weeks: 1)).text
            == "Kept 1 of 7 planned sessions over the last 1 weeks, 14% adherence.")
        #expect(source.answerCoachQuery(.adherence(weeks: 2)).text
            == "Kept 1 of 14 planned sessions over the last 2 weeks, 7% adherence.")
    }

    @Test("recovery: an untrained muscle is fully recovered; a trained one reports a percent")
    func recovery() throws {
        let store = try makeStore()
        let (_, routine) = benchRoutine(store)
        logSession(store, routine: routine)
        let source = CoachFactsSource(store: store, unit: .kg)
        #expect(source.answerCoachQuery(.recovery(muscle: "calves")).text
            == "Calves hasn't been trained in the last two weeks: fully recovered.")
        let chest = source.answerCoachQuery(.recovery(muscle: "Chest")).text
        #expect(chest.hasPrefix("Chest is "))
        #expect(chest.contains("% recovered."))
    }
}
