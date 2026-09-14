import Foundation

/// A bar the user loads plates onto.
public struct Bar: Hashable, Sendable {
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
public struct PlateStock: Hashable, Sendable {
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
public struct PlateLoad: Hashable, Sendable {
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

    /// Half a gram per side. Wide enough to absorb the float drift of plate sizes that are
    /// really pound values in kg (45 lb = 20.4116… kg), narrow enough that it never merges two
    /// real rungs — the smallest micro-plate pair anyone stocks is 500 g.
    static let epsilon = 0.0004

    /// Safety valve on `combinations`: sums collapse onto the plate sizes' common lattice as
    /// they are built, so a real inventory produces a few hundred entries. This only guards a
    /// pathological profile (dozens of mutually-prime plate sizes) from running away.
    static let maxCombinations = 20_000

    public static func load(
        target: Double,
        bar: Bar = .olympic,
        plates: [PlateStock] = PlateStock.standardKg,
        collarsKg: Double = 0
    ) -> Result {
        let base = bar.weightKg + collarsKg
        if target < base - 0.001 { return .tooLight(bar: bar) }

        let perSideTarget = (target - base) / 2
        var belowPlates: [Double] = []
        var abovePlates: [Double]?
        for option in combinations(plates) {
            if option.total <= perSideTarget + epsilon {
                belowPlates = option.plates
            } else {
                abovePlates = option.plates
                break
            }
        }

        let below = PlateLoad(target: target, bar: bar, perSide: belowPlates, collarsKg: collarsKg)
        if below.isExact { return .exact(below) }
        let above = abovePlates.map {
            PlateLoad(target: target, bar: bar, perSide: $0, collarsKg: collarsKg)
        }
        if let above, above.isExact { return .exact(above) }
        return .nearest(below: below, above: above)
    }

    /// The heaviest per-side load this inventory can build without going over `perSideTarget`.
    /// Exposed so callers (and tests) can ask "can this actually be loaded?" with the same
    /// search `load` uses.
    static func perSide(atOrBelow perSideTarget: Double, plates: [PlateStock]) -> [Double] {
        var best: [Double] = []
        for option in combinations(plates) where option.total <= perSideTarget + epsilon {
            best = option.plates
        }
        return best
    }

    /// One loadable per-side combination.
    struct Combination {
        var total: Double
        var plates: [Double]
    }

    /// Every per-side total this inventory can build, lightest first.
    ///
    /// This is a real subset search, not a heaviest-first walk. Plate sizes are not multiples
    /// of one another in general — 25s and 10s with no 5s, or 20×2 alongside 15×4 — so taking
    /// the heaviest plate that still fits both misses loads that exist (30 per side *is*
    /// 15 + 15) and, worse, lets the "next weight up" search skip real rungs and prescribe an
    /// enormous jump.
    ///
    /// Cost: partial sums collapse onto the plate sizes' common lattice as they are built, so
    /// the table holds about `heaviest side load / gcd(plate sizes)` entries — ~115 for a
    /// standard kg set, ~90 for a standard lb one — and the whole search is
    /// O(distinct totals × plate sizes × pairs). Microseconds for any real gym.
    static func combinations(_ plates: [PlateStock]) -> [Combination] {
        if let cached = combinationCache.value(for: plates) { return cached }
        let built = buildCombinations(plates)
        combinationCache.store(built, for: plates)
        return built
    }

    private static func buildCombinations(_ plates: [PlateStock]) -> [Combination] {
        // Keyed by gram-rounded total so sums that differ only by float drift share a slot;
        // the `Double` sum of the stored plates is what callers actually compare against.
        var reached: [Int: [Double]] = [0: []]
        for stock in plates.sorted(by: { $0.weightKg > $1.weightKg }) {
            let pairs = stock.count / 2
            let step = Int((stock.weightKg * 1000).rounded())
            guard pairs > 0, step > 0 else { continue }
            var added: [Int: [Double]] = [:]
            for (key, list) in reached {
                var runningKey = key
                var running = list
                for _ in 0..<pairs {
                    runningKey += step
                    running.append(stock.weightKg)
                    offer(&added, key: runningKey, plates: running)
                }
            }
            for (key, list) in added { offer(&reached, key: key, plates: list) }
            if reached.count >= maxCombinations { break }
        }
        return reached.values
            .map { Combination(total: $0.reduce(0, +), plates: $0) }
            .sorted { lhs, rhs in
                lhs.total == rhs.total
                    ? isBetter(lhs.plates, than: rhs.plates) : lhs.total < rhs.total
            }
    }

    /// Records `plates` for `key` unless something better already reaches it. Order-independent,
    /// so the table — and therefore the load shown on the set row — is the same every run
    /// whatever order the dictionary happens to iterate in.
    private static func offer(_ table: inout [Int: [Double]], key: Int, plates: [Double]) {
        guard let existing = table[key] else {
            table[key] = plates
            return
        }
        if isBetter(plates, than: existing) { table[key] = plates }
    }

    /// Fewest plates wins (fewer to slide on); a tie goes to the heaviest-first list, so
    /// 40 per side is "25 + 15", not "20 + 20".
    private static func isBetter(_ lhs: [Double], than rhs: [Double]) -> Bool {
        if lhs.count != rhs.count { return lhs.count < rhs.count }
        return lhs.lexicographicallyPrecedes(rhs, by: >)
    }

    /// One gym has one inventory, and the same one is asked about over and over — once per
    /// rounded prescription, once per warm-up step, once per keypad keystroke. Memoised so the
    /// search runs once per inventory instead of once per question. Pure input, pure output:
    /// the cache can only ever hand back what `buildCombinations` would have computed.
    private static let combinationCache = CombinationCache()

    private final class CombinationCache: @unchecked Sendable {
        /// A handful of inventories at most: the active profile, maybe an exercise's own bar
        /// setup, and whatever a test is exercising. Cleared wholesale when it grows past this.
        private static let capacity = 16
        private let lock = NSLock()
        private var storage: [[PlateStock]: [Combination]] = [:]

        func value(for plates: [PlateStock]) -> [Combination]? {
            lock.lock()
            defer { lock.unlock() }
            return storage[plates]
        }

        func store(_ combinations: [Combination], for plates: [PlateStock]) {
            lock.lock()
            defer { lock.unlock() }
            if storage.count >= Self.capacity { storage.removeAll(keepingCapacity: true) }
            storage[plates] = combinations
        }
    }
}
