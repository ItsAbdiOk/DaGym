import Foundation
import GymCore
import Testing

@testable import DaGym

/// The redesign's three-field set keypad: effort typing, field hints, and the header's volume
/// tile. Split from `FeatureWorkoutTests` to keep that suite under the type-length cap.
@MainActor
@Suite("Set keypad")
struct SetKeypadSheetTests {
    @Test("a typed rating only lands once it reads as one: RPE 5–10, RIR 0–5")
    func setKeypadEffortTyping() {
        // "1" on the way to "10" is not RPE 1.
        #expect(SetKeypadSheet.effort(typed: 1, scale: .rpe) == nil)
        #expect(SetKeypadSheet.effort(typed: 10, scale: .rpe)?.rpe == 10)
        #expect(SetKeypadSheet.effort(typed: 8.5, scale: .rpe)?.rpe == 8.5)
        #expect(SetKeypadSheet.effort(typed: 2, scale: .rir)?.rir == 2)
        #expect(SetKeypadSheet.effort(typed: 7, scale: .rir) == nil)
    }

    @Test("the keypad hint follows the selected field")
    func setKeypadHints() {
        let bench = ExerciseInfo(name: "Bench", primary: [.chest], equipment: "Barbell", bar: .olympic)
        let dumbbell = ExerciseInfo(
            name: "Curl", primary: [.biceps], equipment: "Dumbbell", bar: nil, isPerSide: true
        )
        let set = SetEntry(weightKg: 80, reps: 8, previousWeightKg: 77.5, previousReps: 8)
        func hint(_ field: SetKeypadSheet.Field, _ exercise: ExerciseInfo, effort: Effort? = nil) -> String {
            SetKeypadSheet.hint(
                for: field,
                context: .init(exercise: exercise, set: set, effort: effort, scale: .rpe, format: { "\($0)" })
            )
        }
        #expect(hint(.weight, bench) == "Plate maths updates as you type.")
        #expect(hint(.weight, dumbbell) == "Per side — enter the weight in one hand.")
        #expect(hint(.reps, bench) == "Last time 77.5 × 8.")
        #expect(hint(.effort, bench).hasPrefix("Optional."))
        #expect(hint(.effort, bench, effort: Effort(rpe: 8)).hasPrefix("RPE 8 — "))
    }

    @Test("the header's volume tile reads tonnes for kg lifters and pounds for lb lifters")
    func volumeTile() {
        let preferences = Preferences(suite: UserDefaults(suiteName: "volume-tile-\(UUID())") ?? .standard)
        preferences.weightUnit = .kg
        let kg = ActiveWorkoutView.volumeTile(kg: 2240, preferences: preferences)
        #expect(kg.value == "2.2")
        #expect(kg.suffix == "t")
        preferences.weightUnit = .lb
        let lb = ActiveWorkoutView.volumeTile(kg: 2240, preferences: preferences)
        #expect(lb.suffix == "lb")
        #expect(lb.value.hasPrefix("4"))
    }
}
