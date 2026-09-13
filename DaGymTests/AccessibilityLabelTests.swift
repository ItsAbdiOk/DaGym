import GymCore
import Testing

@testable import DaGym

/// Pure label-building helpers extracted for VoiceOver strings — no SwiftUI rendering
/// involved, so these are plain input/output checks.
@Suite("Accessibility label helpers")
struct AccessibilityLabelTests {
    @Test("working set reads weight, reps and done state without doubling 'set'")
    func workingSetLabel() {
        let label = SetRowAccessibility.label(
            kind: .working, weight: "82.5", reps: "8", unit: "kg", done: true
        )

        #expect(label == "Set, 82.5 kg by 8 reps, done")
    }

    @Test("not-done set says so")
    func notDoneSetLabel() {
        let label = SetRowAccessibility.label(
            kind: .working, weight: "60", reps: "10", unit: "kg", done: false
        )

        #expect(label.hasSuffix("not done"))
    }

    @Test("warm-up set names its kind")
    func warmupSetLabel() {
        let label = SetRowAccessibility.label(kind: .warmup, weight: "40", reps: "10", unit: "kg", done: true)

        #expect(label == "Warm-up set, 40 kg by 10 reps, done")
    }

    @Test("drop set's display name already says 'set', so it isn't repeated")
    func dropSetLabelDoesNotDoubleSet() {
        let label = SetRowAccessibility.label(kind: .drop, weight: "50", reps: "6", unit: "kg", done: false)

        #expect(label == "Drop set, 50 kg by 6 reps, not done")
    }

    @Test("AMRAP set reads AMRAP before reps")
    func amrapSetLabel() {
        let label = SetRowAccessibility.label(
            kind: .amrap, weight: "70", reps: "AMRAP", unit: "kg", done: false
        )

        #expect(label == "AMRAP set, 70 kg by AMRAP reps, not done")
    }

    @Test("empty intensity map reads as nothing highlighted")
    func emptyBodyMapLabel() {
        #expect(BodyMapAccessibility.label(intensity: [:]) == "Body map, nothing highlighted")
    }

    @Test("zero-intensity muscles are treated as inert, not highlighted")
    func zeroIntensityIsInert() {
        #expect(BodyMapAccessibility.label(intensity: [.chest: 0]) == "Body map, nothing highlighted")
    }

    @Test("highlighted muscles are named and sorted for a stable reading order")
    func highlightedMusclesAreSortedByName() {
        let label = BodyMapAccessibility.label(intensity: [.chest: 1, .delts: 0.6, .biceps: 0.4])

        #expect(label == "Body map: Biceps, Chest, Delts")
    }
}
