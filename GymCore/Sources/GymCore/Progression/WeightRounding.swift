import Foundation

/// The grid a prescribed load must land on — a property of the equipment, not
/// of the progression rule. Barbells round onto loadable plate pairs; dumbbells,
/// machines and kettlebells step in fixed increments; bodyweight/assisted loads
/// aren't rounded at all.
public enum LoadGrid: Hashable, Sendable {
    /// A bar loaded from a plate inventory (see `PlateCalculator`). Nothing lands
    /// below the empty bar — a barbell can't hold 15 kg.
    case plates(bar: Bar, plates: [PlateStock], collarsKg: Double)
    /// Fixed steps, e.g. 2 kg dumbbells, a 5 kg machine stack, 4 kg kettlebells.
    case step(Double)
    /// No rounding — bodyweight, assisted, cable stacks with micro-plates.
    case free
    /// Equipment not known: `.plates` at or above the bar, and the smallest plate
    /// pair as a step below it (a 12 kg load must be a dumbbell or a stack).
    case unknown(bar: Bar, plates: [PlateStock], collarsKg: Double)

    /// The nearest weight on this grid, whichever side of `target` it falls on.
    public func nearest(_ target: Double) -> Double {
        switch self {
        case .plates(let bar, let plates, let collarsKg):
            return Self.nearestOnBar(target, bar: bar, plates: plates, collarsKg: collarsKg)
        case .step(let step):
            guard step > 0 else { return target }
            return (target / step).rounded() * step
        case .free:
            return target
        case .unknown(let bar, let plates, let collarsKg):
            guard target < bar.weightKg + collarsKg - 0.001 else {
                return LoadGrid.plates(bar: bar, plates: plates, collarsKg: collarsKg).nearest(target)
            }
            return Self.underBarGrid(plates).nearest(target)
        }
    }

    /// The heaviest grid weight at or below `target`. Deloads use this so they
    /// never round up past the stalled weight.
    public func nearestBelow(_ target: Double) -> Double {
        switch self {
        case .plates(let bar, let plates, let collarsKg):
            switch PlateCalculator.load(target: target, bar: bar, plates: plates, collarsKg: collarsKg) {
            case .tooLight:
                return bar.weightKg + collarsKg
            case .exact(let load):
                return load.total
            case .nearest(let below, _):
                return below?.total ?? bar.weightKg + collarsKg
            }
        case .step(let step):
            guard step > 0 else { return target }
            return ((target + 0.001) / step).rounded(.down) * step
        case .free:
            return target
        case .unknown(let bar, let plates, let collarsKg):
            guard target < bar.weightKg + collarsKg - 0.001 else {
                return LoadGrid.plates(bar: bar, plates: plates, collarsKg: collarsKg).nearestBelow(target)
            }
            return Self.underBarGrid(plates).nearestBelow(target)
        }
    }

    /// The lightest grid weight strictly above `current`. Increases use this when the
    /// rule's increment is smaller than the grid step, so "+1 kg" on a 2.5 kg grid
    /// still moves the load instead of silently repeating it.
    public func nearestAbove(_ current: Double) -> Double {
        switch self {
        case .plates(let bar, let plates, let collarsKg):
            return Self.nearestAboveOnBar(current, bar: bar, plates: plates, collarsKg: collarsKg)
        case .step(let step):
            guard step > 0 else { return current }
            return ((current + 0.001) / step).rounded(.down) * step + step
        case .free:
            return current
        case .unknown(let bar, let plates, let collarsKg):
            let base = bar.weightKg + collarsKg
            guard current < base - 0.001 else {
                return LoadGrid.plates(bar: bar, plates: plates, collarsKg: collarsKg).nearestAbove(current)
            }
            return min(Self.underBarGrid(plates).nearestAbove(current), base)
        }
    }

    private static func nearestOnBar(
        _ target: Double, bar: Bar, plates: [PlateStock], collarsKg: Double
    ) -> Double {
        switch PlateCalculator.load(target: target, bar: bar, plates: plates, collarsKg: collarsKg) {
        case .tooLight:
            return bar.weightKg + collarsKg
        case .exact(let load):
            return load.total
        case .nearest(let below, let above):
            guard let below else { return above?.total ?? bar.weightKg + collarsKg }
            guard let above else { return below.total }
            return (target - below.total) <= (above.total - target) ? below.total : above.total
        }
    }

    private static func nearestAboveOnBar(
        _ current: Double, bar: Bar, plates: [PlateStock], collarsKg: Double
    ) -> Double {
        let base = bar.weightKg + collarsKg
        guard current >= base - 0.001 else { return base }
        let probe = PlateCalculator.load(
            target: current + 0.01, bar: bar, plates: plates, collarsKg: collarsKg
        )
        switch probe {
        case .tooLight:
            return base
        case .exact(let load):
            return load.total
        case .nearest(let below, let above):
            if let above { return above.total }
            return max(below?.total ?? current, current)
        }
    }

    /// A target under the bar can't be on the bar at all — it's a dumbbell, a
    /// kettlebell, a cable stack. Step it by the smallest plate pair instead of
    /// snapping it up to an empty bar.
    private static func underBarGrid(_ plates: [PlateStock]) -> LoadGrid {
        let smallest = plates.filter { $0.count >= 2 }.map(\.weightKg).min()
        return .step(smallest.map { $0 * 2 } ?? TrainingConstants.defaultStepKg)
    }
}
