import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// The spec's crown table: 2.5 kg or 5 lb for barbells, 2 kg dumbbells, 1 rep, 5 kg assistance,
/// 15 s when scrubbing rest.
@Suite("Crown detents per logging style")
struct CrownDetentTests {
    private func exercise(
        _ style: ExerciseInfo.LoggingStyle, incrementKg: Double, equipment: String
    ) -> ExerciseInfo {
        ExerciseInfo(
            name: "x", primary: [], equipment: equipment, incrementKg: incrementKg, loggingStyle: style
        )
    }

    @Test("a barbell steps 2.5 kg or 5 lb")
    func barbell() {
        let bench = exercise(.weightReps, incrementKg: 2.5, equipment: "barbell")
        #expect(CrownDetents.step(for: .weight, exercise: bench, unit: .kg) == 2.5)
        #expect(CrownDetents.step(for: .weight, exercise: bench, unit: .lb) == 5)
    }

    @Test("a 2 kg increment steps 2 kg, and 2.5 lb below the 2 kg increment")
    func dumbbell() {
        let incline = exercise(.weightReps, incrementKg: 2, equipment: "dumbbell")
        #expect(CrownDetents.step(for: .weight, exercise: incline, unit: .kg) == 2)
        #expect(CrownDetents.step(for: .weight, exercise: incline, unit: .lb) == 5)
        let light = exercise(.weightReps, incrementKg: 1, equipment: "dumbbell")
        #expect(CrownDetents.step(for: .weight, exercise: light, unit: .lb) == 2.5)
    }

    /// The spec's "2 kg dumbbells" is a claim about the library, not the formula: every
    /// dumbbell the watch's sample store seeds must actually carry the 2 kg increment the
    /// crown reads, or the test above proves nothing about a real page.
    @Test("every seeded dumbbell carries the 2 kg increment the crown steps by")
    @MainActor
    func seededDumbbells() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: container.mainContext, photoContext: nil)
        WatchSampleSeeder.seed(store: store)

        let dumbbells = store.exercises().filter { $0.equipment == "dumbbell" }

        #expect(dumbbells.count == 3)
        for dumbbell in dumbbells {
            #expect(CrownDetents.step(for: .weight, exercise: dumbbell, unit: .kg) == 2, "\(dumbbell.name)")
        }
        withExtendedLifetime(container) {}
    }

    @Test("reps step one, assistance 5 kg, RPE half a point, rest 15 s")
    func otherFields() {
        let dip = exercise(.assisted, incrementKg: 5, equipment: "machine")
        #expect(CrownDetents.step(for: .reps, exercise: dip, unit: .kg) == 1)
        #expect(CrownDetents.step(for: .assistance, exercise: dip, unit: .kg) == 5)
        #expect(CrownDetents.step(for: .assistance, exercise: dip, unit: .lb) == 10)
        #expect(CrownDetents.step(for: .effort, exercise: dip, unit: .kg) == 0.5)
        #expect(CrownDetents.restSeconds == 15)
    }

    @Test("a half-kilo floor keeps an unset increment from freezing the crown")
    func floor() {
        let odd = exercise(.weightReps, incrementKg: 0, equipment: "cable")
        #expect(CrownDetents.step(for: .weight, exercise: odd, unit: .kg) == 0.5)
    }

    @Test("ranges: RPE 5–10, reps 0–100, weight 0–1000")
    func ranges() {
        #expect(CrownDetents.range(for: .effort) == 5...10)
        #expect(CrownDetents.range(for: .reps) == 0...100)
        #expect(CrownDetents.range(for: .weight) == 0...1000)
        #expect(CrownDetents.range(for: .assistance) == 0...1000)
    }
}

/// The full-screen rest reads crown *movement*, not position: the countdown keeps falling under
/// the dial, so an absolute target drifted by however long the lifter waited before turning.
@Suite("Crown rest scrubbing")
struct CrownRestScrubberTests {
    @Test("one detent up after a wait adds fifteen seconds, not the drift plus fifteen")
    func detentAfterWait() {
        // Rest started at 90 s, crown parked at 90; fifteen seconds pass (remaining 75) with
        // the crown untouched, then one detent up.
        var scrubber = CrownRestScrubber(position: 90)
        #expect(scrubber.turned(to: 105) == 15)
        #expect(scrubber.turned(to: 120) == 15)
        #expect(scrubber.turned(to: 105) == -15)
    }

    @Test("a slow turn accumulates fractions into whole detents")
    func fractionsCarry() {
        var scrubber = CrownRestScrubber(position: 300)
        #expect(scrubber.turned(to: 307) == 0)
        #expect(scrubber.turned(to: 314) == 0)
        #expect(scrubber.turned(to: 316) == 15)
        #expect(scrubber.turned(to: 331) == 15)
        #expect(scrubber.turned(to: 300) == -30)
    }
}
