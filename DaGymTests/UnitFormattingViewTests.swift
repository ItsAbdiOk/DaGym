import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("Unit-aware view formatting")
struct UnitFormattingViewTests {
    // MARK: - Milestones (MilestoneCopy)

    @Test("locked lifetime-tonnage subtitle ends in lb for an lb preference")
    func lockedSubtitleEndsInLb() {
        let text = MilestoneCopy.lockedSubtitle(metric: .lifetimeTonnageKg, nextThreshold: 5000, unit: .lb)
        #expect(text.hasSuffix("lb lifetime"))
    }

    @Test("locked lifetime-tonnage subtitle ends in kg for a kg preference")
    func lockedSubtitleEndsInKg() {
        let text = MilestoneCopy.lockedSubtitle(metric: .lifetimeTonnageKg, nextThreshold: 5000, unit: .kg)
        #expect(text.hasSuffix("kg lifetime"))
    }

    @Test("earned tier threshold label ends in lb for an lb preference")
    func thresholdLabelEndsInLb() {
        let text = MilestoneCopy.thresholdLabel(metric: .lifetimeTonnageKg, threshold: 5000, unit: .lb)
        #expect(text.hasSuffix("lb lifetime"))
    }

    @Test("non-weight metrics are unaffected by unit")
    func nonWeightMetricsIgnoreUnit() {
        let lb = MilestoneCopy.lockedSubtitle(metric: .workoutCount, nextThreshold: 20, unit: .lb)
        let kg = MilestoneCopy.lockedSubtitle(metric: .workoutCount, nextThreshold: 20, unit: .kg)
        #expect(lb == kg)
    }

    // MARK: - GymCore formatters, called the way the views call them

    @Test("PersonalRecords.formatLine ends in lb for an lb preference")
    func personalRecordLineEndsInLb() {
        let record = PersonalRecord(kind: .maxWeight, value: 61.235, weightKg: 61.235, reps: 1, date: .now)
        let line = PersonalRecords.formatLine(record, unit: .lb)
        #expect(line.hasSuffix("lb"))
        #expect(!line.contains("kg"))
    }

    // MARK: - 1RM calculator stepper (OneRepMaxStep)

    @Test("1RM stepper in lb moves the displayed value by 5 lb")
    func oneRepMaxStepperMovesByFiveLb() {
        let step = OneRepMaxStep.stepKg(for: .lb)
        let start = WeightUnit.lb.toKg(200)
        let startDisplay = Double(WeightUnit.lb.format(kg: start)) ?? 0
        let nextDisplay = Double(WeightUnit.lb.format(kg: start + step)) ?? 0
        #expect(nextDisplay - startDisplay == 5)
    }

    @Test("1RM stepper in kg keeps its existing 1 kg step")
    func oneRepMaxStepperKeepsKgStep() {
        #expect(OneRepMaxStep.stepKg(for: .kg) == 1)
    }

    // MARK: - Progression rule increment stepper (RuleIncrementStep)

    @Test("rule increment stepper in lb steps by a whole pound")
    func ruleIncrementStepperStepsByOnePound() {
        #expect(RuleIncrementStep.stepKg(for: .lb) == WeightUnit.lb.toKg(1))
    }

    @Test("rule increment stepper in kg keeps its existing half-kg step")
    func ruleIncrementStepperKeepsHalfKgStep() {
        #expect(RuleIncrementStep.stepKg(for: .kg) == 0.5)
    }
}
