import Testing
@testable import GymCore

@Suite("Plate calculator")
struct PlateCalculatorTests {
    @Test("100 kg on an Olympic bar is 25 + 15 per side")
    func exact() throws {
        guard case .exact(let load) = PlateCalculator.load(target: 100) else {
            Issue.record("expected exact load")
            return
        }
        #expect(load.perSide == [25, 15])
        #expect(load.total == 100)
        #expect(load.perSideDescription == "25 + 15")
    }

    @Test("bar only when target equals the bar")
    func barOnly() {
        guard case .exact(let load) = PlateCalculator.load(target: 20) else {
            Issue.record("expected exact load")
            return
        }
        #expect(load.perSide.isEmpty)
        #expect(load.perSideDescription.isEmpty)
    }

    @Test("below the bar is too light")
    func tooLight() {
        #expect(PlateCalculator.load(target: 15) == .tooLight(bar: .olympic))
    }

    @Test("respects pair counts: only two 15s means 50 kg uses 10 + 5")
    func pairs() {
        guard case .exact(let load) = PlateCalculator.load(target: 50) else {
            Issue.record("expected exact load")
            return
        }
        #expect(load.perSide == [15])
        guard case .exact(let heavy) = PlateCalculator.load(target: 80) else {
            Issue.record("expected exact load")
            return
        }
        // 30 per side: one 25 and one 5, not 15 + 15 (only one pair of 15s).
        #expect(heavy.perSide == [25, 5])
    }

    @Test("unloadable target reports nearest below and above")
    func nearest() {
        let coarse = [PlateStock(weightKg: 20, count: 4), PlateStock(weightKg: 10, count: 2)]
        guard case .nearest(let below, let above) = PlateCalculator.load(target: 65, plates: coarse) else {
            Issue.record("expected nearest")
            return
        }
        #expect(below?.total == 60)
        #expect(above?.total == 80)
    }

    @Test("collars add to the bar weight")
    func collars() {
        guard case .exact(let load) = PlateCalculator.load(target: 65, collarsKg: 5) else {
            Issue.record("expected exact load")
            return
        }
        #expect(load.perSide == [20])
        #expect(load.total == 65)
    }
}
