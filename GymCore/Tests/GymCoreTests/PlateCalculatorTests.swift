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

/// Awkward, real inventories — the ones the canonical "one of everything" set hides. Every
/// case here was a weight the old heaviest-first walk either refused to build or skipped past.
@Suite("Plate calculator: awkward inventories")
struct PlateCalculatorAwkwardTests {
    /// 25s and 10s, no 5s: nothing is a multiple of the smallest plate.
    static let coarse = [PlateStock(weightKg: 25, count: 4), PlateStock(weightKg: 10, count: 2)]
    /// One pair of 20s but two pairs of 15s: 30 per side is 15 + 15, never 20 + something.
    static let mixed = [PlateStock(weightKg: 20, count: 2), PlateStock(weightKg: 15, count: 4)]

    /// One bar and what's on the rack next to it.
    struct Rack {
        var name: String
        var bar: Bar
        var plates: [PlateStock]
    }

    /// True when `weight` is a weight this bar and inventory can actually be loaded to.
    static func isLoadable(_ weight: Double, bar: Bar, plates: [PlateStock]) -> Bool {
        switch PlateCalculator.load(target: weight, bar: bar, plates: plates) {
        case .exact: return true
        case .tooLight, .nearest: return false
        }
    }

    /// The heaviest weight this inventory can reach, past which "next one up" has no answer.
    static func ceiling(bar: Bar, plates: [PlateStock]) -> Double {
        bar.weightKg + (PlateCalculator.combinations(plates).last?.total ?? 0) * 2
    }

    @Test("70 kg is loadable from 25s alone, so 40 kg steps up to 70 — not 120")
    func nextAboveSkipsNoRung() {
        #expect(PlateCalculator.combinations(Self.coarse).map(\.total).contains(25))
        guard case .exact(let load) = PlateCalculator.load(target: 70, plates: Self.coarse) else {
            Issue.record("70 kg is 25 per side and must be exact")
            return
        }
        #expect(load.perSide == [25])
        let grid = LoadGrid.plates(bar: .olympic, plates: Self.coarse, collarsKg: 0)
        #expect(grid.nearestAbove(40) == 70)
        // The old lattice walk only tried 40 + k×(2 × smallest plate) = 40, 60, 80, 100, 120 and
        // landed on 120: an 80 kg jump from a 40 kg lifter.
        #expect(grid.nearestAbove(40) != 120)
    }

    @Test("30 per side is 15 + 15 when there is only one pair of 20s")
    func subsetSearchBeatsHeaviestFirst() {
        guard case .exact(let load) = PlateCalculator.load(target: 80, plates: Self.mixed) else {
            Issue.record("80 kg is 15 + 15 per side and must be exact")
            return
        }
        #expect(load.perSide == [15, 15])
        #expect(load.total == 80)
    }

    @Test("a 15 kg bar shifts every rung")
    func womensBar() {
        guard case .exact(let load) = PlateCalculator.load(target: 65, bar: .womens) else {
            Issue.record("65 kg on a 15 kg bar is 25 per side")
            return
        }
        #expect(load.perSide == [25])
        #expect(PlateCalculator.load(target: 60, bar: .womens, plates: Self.coarse)
            == .nearest(
                below: PlateLoad(target: 60, bar: .womens, perSide: [10], collarsKg: 0),
                above: PlateLoad(target: 60, bar: .womens, perSide: [25], collarsKg: 0)
            ))
    }

    @Test("lb plates on a kg-seeded 20 kg bar are still searched properly")
    func poundPlatesKgBar() {
        let plates = WeightUnit.plateStock(for: .lb)
        let grid = LoadGrid.plates(bar: .olympic, plates: plates, collarsKg: 0)
        let next = grid.nearestAbove(20)
        #expect(next > 20)
        #expect(Self.isLoadable(next, bar: .olympic, plates: plates))
    }

    @Test("an empty rack can only be the bar")
    func emptyInventory() {
        #expect(PlateCalculator.combinations([]).count == 1)
        guard case .exact(let load) = PlateCalculator.load(target: 20, plates: []) else {
            Issue.record("the bar itself is exact")
            return
        }
        #expect(load.perSide.isEmpty)
        guard case .nearest(let below, let above) = PlateCalculator.load(target: 60, plates: []) else {
            Issue.record("nothing above the bar is loadable")
            return
        }
        #expect(below?.total == 20)
        #expect(above == nil)
    }

    @Test("single plates (odd counts) are never used: a pair or nothing")
    func oddCounts() {
        let single = [PlateStock(weightKg: 20, count: 1), PlateStock(weightKg: 5, count: 3)]
        #expect(PlateCalculator.combinations(single).map(\.total) == [0, 5])
    }

    @Test("a fixed machine stack rounds on its own step, not on plates")
    func machineStack() {
        let stack = LoadGrid.step(5)
        #expect(stack.nearest(63) == 65)
        #expect(stack.nearestBelow(63) == 60)
        #expect(stack.nearestAbove(60) == 65)
    }

    /// Property: across a range of targets and several awkward inventories, the grid never
    /// hands back a weight the plate search cannot build.
    @Test("nearest and nearestAbove always return loadable weights")
    func everyRoundedWeightIsLoadable() {
        let inventories: [Rack] = [
            Rack(name: "25/10, no 5s", bar: .olympic, plates: Self.coarse),
            Rack(name: "20×2 + 15×4", bar: .olympic, plates: Self.mixed),
            Rack(name: "women's bar, standard kg", bar: .womens, plates: PlateStock.standardKg),
            Rack(name: "standard kg", bar: .olympic, plates: PlateStock.standardKg),
            Rack(
                name: "standard lb", bar: WeightUnit.lb.defaultBar,
                plates: WeightUnit.plateStock(for: .lb)
            ),
            Rack(name: "empty rack", bar: .olympic, plates: [])
        ]
        for rack in inventories {
            let (name, bar, plates) = (rack.name, rack.bar, rack.plates)
            let grid = LoadGrid.plates(bar: bar, plates: plates, collarsKg: 0)
            let top = Self.ceiling(bar: bar, plates: plates)
            for step in 0...600 {
                let target = Double(step) * 0.5
                let nearest = grid.nearest(target)
                #expect(
                    Self.isLoadable(nearest, bar: bar, plates: plates),
                    "\(name): nearest(\(target)) = \(nearest) cannot be loaded"
                )
                // Above the top of the rack there is no next rung; the grid says so by
                // returning the target unchanged.
                guard target < top - 0.001 else { continue }
                let above = grid.nearestAbove(target)
                #expect(above > target - 0.001)
                #expect(
                    Self.isLoadable(above, bar: bar, plates: plates),
                    "\(name): nearestAbove(\(target)) = \(above) cannot be loaded"
                )
                let below = grid.nearestBelow(target)
                #expect(
                    Self.isLoadable(below, bar: bar, plates: plates) || below < bar.weightKg,
                    "\(name): nearestBelow(\(target)) = \(below) cannot be loaded"
                )
            }
        }
    }
}
