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
}
