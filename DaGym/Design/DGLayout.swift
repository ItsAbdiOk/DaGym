import SwiftUI

/// Spacing (4 pt grid), radii and tap targets.
enum DGSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    /// Inside rows.
    static let s3: CGFloat = 12
    /// Screen gutter.
    static let s4: CGFloat = 16
    /// Card padding.
    static let s5: CGFloat = 20
    /// Between cards.
    static let s6: CGFloat = 24
    /// Section break.
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s14: CGFloat = 56
}

enum DGRadius {
    static let chip: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 26
    static let sheet: CGFloat = 32
    static let pill: CGFloat = 999
}

enum DGTap {
    /// Absolute floor.
    static let min: CGFloat = 44
    /// Set-row check.
    static let done: CGFloat = 52
    /// Set row height.
    static let rowHeight: CGFloat = 56
}

/// Motion tokens. Nothing a thumb is aiming at may move.
enum DGMotion {
    static let tap = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.11)
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.26)
    static let sheet = Animation.interpolatingSpring(stiffness: 220, damping: 26)
    static let timer = Animation.linear(duration: 1)
    static let celebrate = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.72)
}
