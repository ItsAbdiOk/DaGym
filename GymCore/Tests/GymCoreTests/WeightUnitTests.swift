import Foundation
import Testing
@testable import GymCore

@Suite("Weight unit")
struct WeightUnitTests {
    @Test("kg round-trips exactly")
    func kgRoundTrip() {
        let unit = WeightUnit.kg
        #expect(unit.display(kg: 82.5) == 82.5)
        #expect(unit.toKg(82.5) == 82.5)
    }

    @Test("lb round-trips within a gram of tolerance")
    func lbRoundTrip() {
        let unit = WeightUnit.lb
        let kg = 100.0
        let lb = unit.display(kg: kg)
        #expect(abs(lb - 220.462) < 0.001)
        #expect(abs(unit.toKg(lb) - kg) < 0.001)
    }

    @Test("kg formatting drops a trailing .0 and keeps quarter-kg precision")
    func kgFormatting() {
        let unit = WeightUnit.kg
        #expect(unit.format(kg: 82.5) == "82.5")
        #expect(unit.format(kg: 100) == "100")
        #expect(["80.25", "80.2", "80.3"].contains(unit.format(kg: 80.25)))
    }

    @Test("lb formatting rounds the display value to the nearest half pound")
    func lbFormattingRounds() {
        let unit = WeightUnit.lb
        // 100 kg -> 220.462 lb, rounds to 220.5.
        #expect(unit.format(kg: 100) == "220.5")
        // 61.2 kg -> 134.9 lb, rounds to 135 and drops the trailing .0.
        #expect(unit.format(kg: 61.2) == "135")
    }

    @Test("default increment: 2.5 kg, 5 lb expressed in kg")
    func defaultIncrement() {
        #expect(WeightUnit.kg.defaultIncrementKg == 2.5)
        #expect(abs(WeightUnit.lb.defaultIncrementKg - 2.268) < 0.001)
    }

    @Test("kg plate stock matches the standard commercial set")
    func kgPlateStock() {
        let stock = WeightUnit.plateStock(for: .kg)
        #expect(stock == PlateStock.standardKg)
    }

    @Test("lb plate stock covers 45/35/25/10/5/2.5 lb converted to kg")
    func lbPlateStock() {
        let stock = WeightUnit.plateStock(for: .lb)
        #expect(stock.count == 6)
        let heaviest = stock.max { $0.weightKg < $1.weightKg }
        #expect(abs((heaviest?.weightKg ?? 0) - 20.4117) < 0.001)
        let lightest = stock.min { $0.weightKg < $1.weightKg }
        #expect(abs((lightest?.weightKg ?? 0) - 1.134) < 0.001)
    }

    @Test("default bar: 20 kg Olympic, or 45 lb expressed in kg")
    func defaultBar() {
        #expect(WeightUnit.kg.defaultBar.weightKg == 20)
        #expect(abs(WeightUnit.lb.defaultBar.weightKg - 20.4117) < 0.001)
    }

    @Test("case iterable and codable")
    func caseIterableCodable() throws {
        #expect(WeightUnit.allCases == [.kg, .lb])
        let data = try JSONEncoder().encode(WeightUnit.lb)
        let decoded = try JSONDecoder().decode(WeightUnit.self, from: data)
        #expect(decoded == .lb)
    }
}
