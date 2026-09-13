import Foundation

/// A bar the user loads plates onto.
public struct Bar: Equatable, Sendable {
    public var name: String
    public var weightKg: Double

    public init(name: String, weightKg: Double) {
        self.name = name
        self.weightKg = weightKg
    }

    public static let olympic = Bar(name: "Olympic", weightKg: 20)
    public static let womens = Bar(name: "Women's", weightKg: 15)
}

/// One plate size and how many the gym has (total, not pairs).
public struct PlateStock: Equatable, Sendable {
    public var weightKg: Double
    public var count: Int

    public init(weightKg: Double, count: Int) {
        self.weightKg = weightKg
        self.count = count
    }

    /// A typical commercial kg set: enough of everything for one bar.
    public static let standardKg: [PlateStock] = [
        PlateStock(weightKg: 25, count: 4), PlateStock(weightKg: 20, count: 4),
        PlateStock(weightKg: 15, count: 2), PlateStock(weightKg: 10, count: 4),
        PlateStock(weightKg: 5, count: 4), PlateStock(weightKg: 2.5, count: 4),
        PlateStock(weightKg: 1.25, count: 4)
    ]
}

/// Plates for one side of the bar.
public struct PlateLoad: Equatable, Sendable {
    public var target: Double
    public var bar: Bar
    /// Plates per side, heaviest first.
    public var perSide: [Double]
    public var collarsKg: Double

    public var total: Double {
        bar.weightKg + collarsKg + perSide.reduce(0, +) * 2
    }

    public var isExact: Bool { abs(total - target) < 0.001 }

    /// "25 + 5" for the set row; empty string means bar only.
    public var perSideDescription: String {
        perSide.map { Self.format($0) }.joined(separator: " + ")
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// What to put on each side for a target weight.
public enum PlateCalculator {
    public enum Result: Equatable, Sendable {
        /// The target is below the bar (plus collars).
        case tooLight(bar: Bar)
        case exact(PlateLoad)
        /// Not loadable with this inventory; nearest achievable above and below.
        case nearest(below: PlateLoad?, above: PlateLoad?)
    }

    public static func load(
        target: Double,
        bar: Bar = .olympic,
        plates: [PlateStock] = PlateStock.standardKg,
        collarsKg: Double = 0
    ) -> Result {
        let base = bar.weightKg + collarsKg
        if target < base - 0.001 { return .tooLight(bar: bar) }

        let perSide = greedy(perSideTarget: (target - base) / 2, plates: plates)
        let closest = PlateLoad(target: target, bar: bar, perSide: perSide, collarsKg: collarsKg)
        if closest.isExact { return .exact(closest) }

        // Greedy already gives the heaviest load at or below the target
        // (bar only, at worst).
        let below: PlateLoad? = closest

        // For "above", step the target up by the smallest plate pair until it's loadable.
        let smallest = plates.filter { $0.count >= 2 }.map(\.weightKg).min() ?? 0
        var above: PlateLoad?
        if smallest > 0 {
            let step = smallest * 2
            var candidate = target + step - (target - base).truncatingRemainder(dividingBy: step)
            let ceiling = base + plates.reduce(0) { $0 + $1.weightKg * Double($1.count / 2) } * 2
            while candidate <= ceiling + 0.001 {
                let plate = greedy(perSideTarget: (candidate - base) / 2, plates: plates)
                let load = PlateLoad(target: candidate, bar: bar, perSide: plate, collarsKg: collarsKg)
                if load.isExact {
                    above = load
                    break
                }
                candidate += step
            }
        }
        return .nearest(below: below, above: above)
    }

    /// Heaviest plate first, limited to pairs in stock.
    static func greedy(perSideTarget: Double, plates: [PlateStock]) -> [Double] {
        var remaining = perSideTarget
        var result: [Double] = []
        for stock in plates.sorted(by: { $0.weightKg > $1.weightKg }) {
            var pairsLeft = stock.count / 2
            while pairsLeft > 0 && remaining >= stock.weightKg - 0.001 {
                result.append(stock.weightKg)
                remaining -= stock.weightKg
                pairsLeft -= 1
            }
        }
        return result
    }
}
