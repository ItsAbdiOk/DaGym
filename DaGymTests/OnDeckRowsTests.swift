import Foundation
import GymCore
import Testing

@testable import DaGym

@MainActor
@Suite("On-deck card rows")
struct OnDeckRowsTests {
    private func plankEntry() -> WorkoutExerciseEntry {
        let plank = ExerciseInfo(
            name: "Plank", primary: [.abs], equipment: "Bodyweight", restSeconds: 60, bar: nil,
            loggingStyle: .timedHold
        )
        let sets = [
            SetEntry(kind: .working, weightKg: 0, reps: 0, targetSeconds: 60),
            SetEntry(kind: .working, weightKg: 0, reps: 0, targetSeconds: 60)
        ]
        return WorkoutExerciseEntry(exercise: plank, sets: sets)
    }

    @Test("an on-deck timed entry lays out hold rows with Start on its first open set")
    func timedEntryShowsStart() {
        let entry = plankEntry()

        #expect(entry.onDeckRows == .timed(startSetID: entry.sets[0].id))
    }

    @Test("Start moves to the next open hold once the first is logged")
    func startMovesToNextOpenHold() {
        var entry = plankEntry()
        entry.sets[0].isDone = true
        entry.sets[0].durationSeconds = 55

        #expect(entry.onDeckRows == .timed(startSetID: entry.sets[1].id))
    }

    @Test("a single-exercise timed session can be started from its on-deck card")
    func singleTimedExerciseIsStartable() {
        let entry = plankEntry()
        let session = WorkoutSession(title: "Core", subtitle: "", startedAt: Date(), exercises: [entry])
        let onDeck = session.onDeckIndex.map { session.exercises[$0] }

        guard case .timed(let startSetID) = onDeck?.onDeckRows, let startSetID else {
            Issue.record("expected a timed on-deck row with a Start target")
            return
        }
        session.startTimedHold(exerciseID: entry.id, setID: startSetID, targetSeconds: 60)

        #expect(session.timedHold?.setID == entry.sets[0].id)
    }

    @Test("a weight × reps entry keeps the loaded set rows")
    func loadedEntryKeepsSetRows() {
        let bench = ExerciseInfo(name: "Bench Press", primary: [.chest], equipment: "Barbell")
        let entry = WorkoutExerciseEntry(exercise: bench, sets: [SetEntry(weightKg: 80, reps: 8)])

        #expect(entry.onDeckRows == .loaded)
    }
}
