import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("Equipment profile units")
struct EquipmentProfileUnitTests {
    @Test("the lb plate set offers 45/35/25/10/5/2.5 lb, not the kg set")
    func lbPlateSetIsLbSized() {
        let weightsKg = EquipmentStep.standardWeightsKg(for: .lb)
        let backToLb = weightsKg.map { WeightUnit.lb.format(kg: $0) }
        #expect(Set(backToLb) == ["45", "35", "25", "10", "5", "2.5"])
    }

    @Test("the kg plate set is unchanged from the existing standard kg sizes")
    func kgPlateSetIsUnchanged() {
        let weightsKg = EquipmentStep.standardWeightsKg(for: .kg)
        #expect(Set(weightsKg) == Set(PlateStock.standardKg.map(\.weightKg)))
    }

    @Test("a 45/35/25 lb plate count round-trips to kg and back through the same conversion")
    func plateCountsRoundTripLbToKgAndBack() {
        // Mirrors what EquipmentProfileView does: convert the lb standard set to kg once (to
        // build the picker rows), save those kg values in a profile, then rebuild the same lb
        // set again (as on a fresh presentation) and look counts up by the recomputed kg key.
        let lbWeights = EquipmentStep.standardWeightsKg(for: .lb)
        let saved: [Double: Int] = [lbWeights[0]: 4, lbWeights[1]: 4, lbWeights[2]: 2]

        let rebuiltLbWeights = EquipmentStep.standardWeightsKg(for: .lb)
        let counts = rebuiltLbWeights.map { saved[$0] ?? 0 }

        #expect(counts[0] == 4)
        #expect(counts[1] == 4)
        #expect(counts[2] == 2)
        #expect(WeightUnit.lb.format(kg: rebuiltLbWeights[0]) == "45")
        #expect(WeightUnit.lb.format(kg: rebuiltLbWeights[1]) == "35")
        #expect(WeightUnit.lb.format(kg: rebuiltLbWeights[2]) == "25")
    }

    @Test("bar/collar stepper in lb steps by a whole pound")
    func barStepperStepsByOnePoundInLb() {
        #expect(EquipmentStep.stepKg(for: .lb) == WeightUnit.lb.toKg(1))
    }

    @Test("bar/collar stepper in kg keeps its existing half-kg step")
    func barStepperKeepsHalfKgStepInKg() {
        #expect(EquipmentStep.stepKg(for: .kg) == 0.5)
    }

    /// The plate list used to key rows on `weightKg`, so two near-identical saved sizes (an
    /// lb-derived value before and after a rounding change) gave `ForEach` duplicate ids.
    @Test("two saved sizes within the tolerance collapse into one row")
    func nearIdenticalExistingSizesShareOneRow() {
        let existing = [PlateStock(weightKg: 20.4116, count: 2), PlateStock(weightKg: 20.4117, count: 4)]
        let rows = EquipmentStep.rows(standard: [20, 10], existing: existing)

        let sizes = rows.map(\.weightKg)
        #expect(sizes.count == Set(sizes).count)
        #expect(rows.filter { abs($0.weightKg - 20.4116) < EquipmentStep.sameSizeToleranceKg }.count == 1)
        #expect(rows.first { abs($0.weightKg - 20.4116) < EquipmentStep.sameSizeToleranceKg }?.count == 6)
        // `count` here is a plate quantity, not a Collection.count.
        // swiftlint:disable:next empty_count
        #expect(rows.contains { $0.weightKg == 20 && $0.count == 0 })
        // swiftlint:disable:next empty_count
        #expect(rows.contains { $0.weightKg == 10 && $0.count == 0 })
    }

    @Test("distinct saved sizes keep their own rows and counts")
    func distinctExistingSizesStaySeparate() {
        let existing = [PlateStock(weightKg: 20, count: 2), PlateStock(weightKg: 10, count: 4)]
        let rows = EquipmentStep.rows(standard: [20, 10, 5], existing: existing)

        #expect(rows.map(\.weightKg) == [20, 10, 5])
        #expect(rows.map(\.count) == [2, 4, 0])
    }
}
