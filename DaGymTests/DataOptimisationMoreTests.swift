import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The rest of the optimisation pass: the one-query Siri lookup, the injected unit provider,
/// and the rest-timer/totals split of `WorkoutSession`.
@MainActor
@Suite("Data optimisation pass — intents, units, session")
struct DataOptimisationMoreTests {
    private let fx = DataOptimisationFixtures()

    @Test("the last-session lookup is one query, and an exercise never trained answers nil")
    func lastSessionIsOneQuery() throws {
        let store = try fx.makeStore()
        let bench = fx.makeBench(store)
        let never = store.createCustomExercise(
            name: "Never", primary: [.calves], equipment: "Machine", style: .weightReps
        )
        let routineID = fx.makeRoutine(store, exerciseID: bench.id)
        fx.logSessions(store, routineID: routineID, count: 4)
        var last: LastSessionIntent.LastSession?
        let trained = fx.queries(store) {
            last = LastSessionIntent.lastSession(exerciseID: bench.id, store: store)
        }
        #expect(trained == 1)
        #expect(last?.weightKg == 75)
        let untrained = fx.queries(store) {
            last = LastSessionIntent.lastSession(exerciseID: never.id, store: store)
        }
        #expect(untrained == 1)
        #expect(last == nil)
    }

    // MARK: - Units

    @Test("the store reads its units from the injected provider, not UserDefaults.standard")
    func unitsAreInjected() throws {
        let store = try fx.makeStore(units: .fixed(weight: .lb))
        #expect(store.preferredWeightUnit == .lb)
        #expect(store.preferredDistanceUnit == .mi)
        let metric = try fx.makeStore(units: .fixed(weight: .kg, distance: .mi))
        #expect(metric.preferredWeightUnit == .kg)
        #expect(metric.preferredDistanceUnit == .mi)
    }

    // MARK: - WorkoutSession totals and rest timer

    @Test("session totals update after every mutation and the rest timer lives on its own state")
    func sessionTotalsAndRestSplit() {
        let bench = ExerciseInfo(name: "Bench", primary: [.chest], equipment: "Barbell")
        let entry = WorkoutExerciseEntry(
            exercise: bench,
            sets: [
                SetEntry(kind: .warmup, weightKg: 40, reps: 10),
                SetEntry(kind: .working, weightKg: 80, reps: 8),
                SetEntry(kind: .working, weightKg: 80, reps: 8)
            ]
        )
        let session = WorkoutSession(title: "Push", subtitle: "", startedAt: Date(), exercises: [entry])
        session.defaultRestSeconds = 0
        #expect(session.volumeKg == 0)
        #expect(session.setsTotal == 2)
        session.exercises[0].sets[1].isDone = true
        #expect(session.volumeKg == 640)
        #expect(session.setsDone == 1)
        #expect(session.musclesHit[.chest] == 1)
        session.exercises[0].sets[2].reps = 5
        session.exercises[0].sets[2].isDone = true
        #expect(session.volumeKg == 640 + 400)
        session.exercises.append(entry)
        #expect(session.setsTotal == 4)

        session.restRemaining = 30
        session.restTotal = 90
        #expect(session.rest.remaining == 30)
        #expect(session.rest.total == 90)
        #expect(session.isResting)
        session.skipRest()
        #expect(session.rest.remaining == 0)
        #expect(!session.isResting)
    }
}
