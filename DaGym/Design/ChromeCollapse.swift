import Foundation

/// Scroll-driven chrome collapse for Active Workout's "chrome sheds on scroll": past a
/// threshold on the way down the nav condenses and the action bar slides away; scrolling
/// back up restores everything. Hysteresis (different thresholds for collapse vs. expand)
/// stops the chrome flickering near the boundary. Pure and UIKit/SwiftUI-free so it's cheap
/// to unit test; the view feeds it `contentOffset.y` from `onScrollGeometryChange`.
struct ChromeCollapseState: Equatable {
    /// Collapse once content has scrolled down past this many points from the top.
    static let collapseThreshold: CGFloat = 80
    /// Once collapsed, expand once the user has scrolled back up this many points from the
    /// deepest offset reached.
    static let expandHysteresis: CGFloat = 24

    private(set) var isCollapsed = false
    private var deepestOffset: CGFloat = 0

    /// Feeds a new `contentOffset.y` reading (0 at rest, positive scrolled down).
    /// Returns whether `isCollapsed` changed, so callers know to animate the transition.
    @discardableResult
    mutating func update(offset: CGFloat) -> Bool {
        let previous = isCollapsed
        if isCollapsed {
            deepestOffset = max(deepestOffset, offset)
            if deepestOffset - offset > Self.expandHysteresis {
                isCollapsed = false
            }
        } else {
            deepestOffset = offset
            if offset > Self.collapseThreshold {
                isCollapsed = true
            }
        }
        return isCollapsed != previous
    }
}
