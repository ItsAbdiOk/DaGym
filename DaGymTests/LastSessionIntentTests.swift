import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("LastSessionIntent")
struct LastSessionIntentTests {
    @Test("the spoken line is in the user's unit")
    func lineInLb() {
        let line = LastSessionIntent.line(weightKg: 80, reps: [8, 8, 7], unit: .lb)

        #expect(line == "\(WeightUnit.lb.format(kg: 80)) lb × 8, 8, 7")
        #expect(LastSessionIntent.line(weightKg: 80, reps: [8], unit: .kg) == "80 kg × 8")
    }

    @Test("numbers and date come from the same workout: the newest with a completed set")
    func lineAndDateAgree() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Lat Pulldown", primary: [.lats], equipment: "Cable", style: .weightReps
        )
        let earlier = Date().addingTimeInterval(-7 * 86_400)

        let done = store.startBackfill(date: earlier, durationMinutes: 60, routineID: nil)
        done.exercises.append(store.autoFilledEntry(for: exercise))
        done.exercises[0].sets[0].weightKg = 60
        done.exercises[0].sets[0].reps = 10
        done.exercises[0].sets[0].isDone = true
        _ = store.finish(session: done)

        let skipped = store.startFreestyle()
        skipped.exercises.append(store.autoFilledEntry(for: exercise))
        _ = store.finish(session: skipped)

        let last = try #require(LastSessionIntent.lastSession(exerciseID: exercise.id, store: store))
        #expect(last.weightKg == 60)
        #expect(last.reps == [10])
        #expect(abs(last.date.timeIntervalSince(earlier)) < 60)
    }
}
