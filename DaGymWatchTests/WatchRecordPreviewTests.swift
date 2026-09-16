import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// The record card previews what `WorkoutStore.evaluatePRs` will bank at finish, so it must
/// estimate from the same load: bar weight for a weight × reps lift, bodyweight plus the added
/// load for a weighted dip or pull-up — the cache it compares against holds the total.
@MainActor
@Suite("Watch record preview load")
struct WatchRecordPreviewTests {
    private func entry(_ style: ExerciseInfo.LoggingStyle, bestE1RM: Double? = nil) -> WorkoutExerciseEntry {
        var info = ExerciseInfo(name: "Dip", primary: [.chest], equipment: "bodyweight", loggingStyle: style)
        info.bestE1RM = bestE1RM
        return WorkoutExerciseEntry(exercise: info, sets: [SetEntry(weightKg: 30, reps: 5)])
    }

    @Test("a weighted-bodyweight set is estimated from bodyweight plus the added load")
    func weightedBodyweightAddsBodyweight() throws {
        let fixture = try makeWatchFixture(seeded: false)
        let asOf = Date()
        _ = fixture.phone.logBodyweight(kg: 80, date: asOf.addingTimeInterval(-3_600))
        let dip = entry(.weightedBodyweight)

        let load = fixture.watch.previewLoadKg(entry: dip, set: dip.sets[0], asOf: asOf)

        #expect(load == 110)
        // The same number the finish-time PR maths uses.
        let performed = PerformedSet(kind: .working, weightKg: 30, reps: 5, bodyweightKg: 80, date: asOf)
        #expect(load == performed.effectiveWeightKg)
        withExtendedLifetime(fixture) {}
    }

    @Test("without a weigh-in the added load stands alone, as it does at finish")
    func weightedBodyweightWithoutBodyweight() throws {
        let fixture = try makeWatchFixture(seeded: false)
        let dip = entry(.weightedBodyweight)
        #expect(fixture.watch.previewLoadKg(entry: dip, set: dip.sets[0], asOf: Date()) == 30)
        withExtendedLifetime(fixture) {}
    }

    @Test("weight × reps reads the bar; other styles have no preview")
    func otherStyles() throws {
        let fixture = try makeWatchFixture(seeded: false)
        _ = fixture.phone.logBodyweight(kg: 80)
        let bench = entry(.weightReps)
        #expect(fixture.watch.previewLoadKg(entry: bench, set: bench.sets[0], asOf: Date()) == 30)
        let pullUp = entry(.bodyweightReps)
        #expect(fixture.watch.previewLoadKg(entry: pullUp, set: pullUp.sets[0], asOf: Date()) == nil)
        withExtendedLifetime(fixture) {}
    }

    @Test("a real weighted-dip record fires the card against the total-load cache, a non-record does not")
    func cardFiresOnTotalLoad() throws {
        let fixture = try makeWatchFixture(seeded: false)
        _ = fixture.phone.logBodyweight(kg: 80)
        let dip = fixture.phone.createCustomExercise(
            name: "Weighted Dip", primary: [.chest], equipment: "bodyweight", style: .weightedBodyweight
        )
        let sets = (0..<2).map { _ in PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 30) }
        let routine = fixture.phone.saveRoutine(
            id: nil, name: "Dips", exercises: [RoutineExerciseDraft(exerciseID: dip.id, sets: sets)]
        )
        fixture.watch.start(routineID: routine.id)
        let session = try #require(fixture.watch.session)
        let entryID = session.exercises[0].id
        // Cached best 110 × 5 (e1RM ≈ 128): +30 × 5 is the same total, not a record.
        let cached = try #require(OneRepMax.estimate(weight: 110, reps: 5))
        session.exercises[0].exercise.bestE1RM = cached

        fixture.watch.updateSet(exerciseID: entryID) { $0.weightKg = 30; $0.reps = 5 }
        fixture.watch.logCurrentSet(exerciseID: entryID)
        #expect(fixture.watch.recordCard == nil)

        fixture.watch.skipRest()
        fixture.watch.updateSet(exerciseID: entryID) { $0.weightKg = 40; $0.reps = 5 }
        fixture.watch.logCurrentSet(exerciseID: entryID)
        let card = try #require(fixture.watch.recordCard)
        #expect(card.newE1RM == OneRepMax.estimate(weight: 120, reps: 5))
        withExtendedLifetime(fixture) {}
    }
}
