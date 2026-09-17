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
    static let lg: CGFloat = 22
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

    /// Reduce Motion-aware variant of a token: a quick cross-fade in place of the eased
    /// move/spring so state still changes instantly without motion. Callers read
    /// `@Environment(\.accessibilityReduceMotion)` and pass it through here rather than
    /// branching at every call site.
    static func aware(_ token: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.001) : token
    }
}

/// `.animation(token, value:)` that reads Reduce Motion itself, so a call site needs neither
/// the environment nor `DGMotion.aware` — every moving or scaling animation in the app goes
/// through this (or `DGMotion.aware` where a `withAnimation` block needs the token directly).
private struct DGAwareAnimation<Value: Equatable>: ViewModifier {
    let token: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(DGMotion.aware(token, reduceMotion: reduceMotion), value: value)
    }
}

/// `.transition(moving)` that falls back to a plain cross-fade under Reduce Motion, so a toast
/// or overlay still appears and disappears without sliding.
private struct DGAwareTransition: ViewModifier {
    let moving: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : moving)
    }
}

extension View {
    /// Reduce Motion-aware `.animation(_:value:)`. Cross-fades stay; moves and scales collapse
    /// to an instant change when the system setting is on.
    func dgAnimation<Value: Equatable>(_ token: Animation, value: Value) -> some View {
        modifier(DGAwareAnimation(token: token, value: value))
    }

    /// Reduce Motion-aware `.transition(_:)`: `moving` normally, `.opacity` when the setting is on.
    func dgTransition(_ moving: AnyTransition) -> some View {
        modifier(DGAwareTransition(moving: moving))
    }
}

extension View {
    /// The one rule for the system tab bar on a pushed screen: a screen with a text input at
    /// the bottom (the coach chat's bar, Insights' "Ask" field) hides it, because a bar
    /// floating over a keyboard-anchored field is two controls fighting for the same edge.
    /// Every other pushed screen keeps it, so a lifter can hop tabs from three levels deep.
    /// Only these two call sites hide the bar; anything new should go through here.
    func dgHidesTabBarForInput() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}
