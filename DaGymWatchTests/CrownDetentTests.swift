import Foundation
import GymCore
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

    @Test("a dumbbell steps 2 kg, and 2.5 lb below the 2 kg increment")
    func dumbbell() {
        let incline = exercise(.weightReps, incrementKg: 2, equipment: "dumbbell")
        #expect(CrownDetents.step(for: .weight, exercise: incline, unit: .kg) == 2)
        #expect(CrownDetents.step(for: .weight, exercise: incline, unit: .lb) == 5)
        let light = exercise(.weightReps, incrementKg: 1, equipment: "dumbbell")
        #expect(CrownDetents.step(for: .weight, exercise: light, unit: .lb) == 2.5)
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
