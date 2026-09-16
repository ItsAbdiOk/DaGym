import Foundation
import Testing

@testable import GymCore

@Suite("MuscleStrength")
struct MuscleStrengthTests {
    private func lift(_ name: String, _ primary: [Muscle], _ e1rm: Double) -> MuscleStrength.Lift {
        MuscleStrength.Lift(exerciseID: UUID(), name: name, primary: primary, e1rmKg: e1rm)
    }

    @Test("top lifts per primary mover, heaviest first, capped, ties by name")
    func topPerMuscle() {
        let lifts = [
            lift("Bench", [.chest, .triceps], 120), lift("Incline", [.chest], 100),
            lift("Dips", [.chest, .triceps], 100), lift("Fly", [.chest], 40),
            lift("Squat", [.quads], 150), lift("Curl", [.biceps], 0)
        ]
        let top = MuscleStrength.top(lifts: lifts, perMuscle: 3)
        #expect(top[.chest]?.map(\.name) == ["Bench", "Dips", "Incline"])
        #expect(top[.triceps]?.map(\.name) == ["Bench", "Dips"])
        #expect(top[.quads]?.map(\.e1rmKg) == [150])
        // A zero e1RM is "never loaded", not a weak lift; secondary movers never file.
        #expect(top[.biceps] == nil)
        #expect(top[.delts] == nil)
    }

    @Test("map intensity: the strongest muscle is 1, the rest scale, a light muscle stays lit")
    func intensity() {
        let top = MuscleStrength.top(lifts: [
            lift("Squat", [.quads], 200), lift("Bench", [.chest], 100), lift("Curl", [.biceps], 20)
        ])
        let map = MuscleStrength.mapIntensity(top)
        #expect(map[.quads] == 1)
        #expect(map[.chest] == 0.5)
        #expect(map[.biceps] == LibraryFacets.minimumLit)
        #expect(map[.lats] == nil)
        #expect(MuscleStrength.mapIntensity([:]).isEmpty)
    }
}
