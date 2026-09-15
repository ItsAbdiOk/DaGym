import GymCore
import Testing

@testable import DaGymWatch

/// The spec's VoiceOver table, as strings: steppers are adjustable values ("Weight, 100
/// kilograms, adjustable" — the trait says "adjustable", the value says the rest), the set row
/// reads as one element first, dots collapse to "2 of 4 sets done", the rest timer speaks at 30
/// seconds and zero only.
@Suite("Watch VoiceOver strings")
struct WatchAccessibilityTests {
    private func stepper(
        _ field: CrownField, _ value: Double, _ unit: WeightUnit, perSide: Bool = false
    ) -> String {
        WatchAccessibility.stepperValue(field: field, value: value, unit: unit, perSide: perSide)
    }

    private func row(
        _ shape: SetShape, _ position: (Int, Int), kg: Double, reps: Int, seconds: Int? = nil
    ) -> String {
        WatchAccessibility.setRow(
            shape: shape, position: position, weightKg: kg, reps: reps, targetSeconds: seconds, unit: .kg
        )
    }

    @Test("a weight stepper speaks its value in the lifter's unit, spelled out")
    func stepperWeight() {
        #expect(stepper(.weight, 100, .kg) == "100 kilograms")
        #expect(stepper(.weight, 100, .lb) == "220.5 pounds")
        #expect(stepper(.assistance, 20, .kg) == "20 kilograms assistance")
    }

    @Test("reps, per-side reps and RPE steppers")
    func stepperOthers() {
        #expect(stepper(.reps, 5, .kg) == "5 reps")
        #expect(stepper(.reps, 8, .kg, perSide: true) == "8 reps per side")
        #expect(stepper(.effort, 8, .kg) == "RPE 8")
    }

    @Test("the set row reads as one element: Set 2 of 4, 100 kilograms by 5 reps")
    func setRow() {
        #expect(row(.standard, (2, 4), kg: 100, reps: 5) == "Set 2 of 4, 100 kilograms by 5 reps")
        #expect(row(.warmup, (2, 2), kg: 60, reps: 5) == "Warm-up 2 of 2, 60 kilograms by 5 reps")
        #expect(row(.bodyweight, (1, 3), kg: 0, reps: 9) == "Set 1 of 3, 9 reps")
        #expect(row(.timedHold, (2, 3), kg: 0, reps: 0, seconds: 45) == "Set 2 of 3, target 0:45")
        #expect(row(.perSide, (1, 3), kg: 24, reps: 16) == "Set 1 of 3, 24 kilograms by 8 reps per side")
        #expect(row(.assisted, (2, 3), kg: 20, reps: 8) == "Set 2 of 3, 20 kilograms assistance by 8 reps")
    }

    @Test("progress dots collapse to '2 of 4 sets done'")
    func dots() {
        #expect(WatchAccessibility.dots(done: 2, total: 4) == "2 of 4 sets done")
    }

    @Test("the rest timer announces at 30 seconds and zero, never every second")
    func restAnnouncements() {
        #expect(WatchAccessibility.restAnnouncement(remaining: 30) != nil)
        #expect(WatchAccessibility.restAnnouncement(remaining: 0) != nil)
        for remaining in [90, 45, 31, 29, 10, 3, 1] {
            #expect(WatchAccessibility.restAnnouncement(remaining: remaining) == nil, "\(remaining)")
        }
    }
}
