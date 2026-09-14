import SwiftUI

/// How hard a control reacts to a finger.
enum DGPressWeight {
    /// Pills, chips, icon buttons, keys: a visible squeeze.
    case control
    /// Full-width cards and tiles: barely a nudge, because scaling a big surface reads as a glitch.
    case card
    /// List and set rows: no scale at all — a wash behind the row instead.
    case row

    var scale: CGFloat {
        switch self {
        case .control: 0.96
        case .card: 0.985
        case .row: 1
        }
    }

    var dimsBackground: Bool { self == .row }

    /// Only small controls need their hit area grown; a card or row already fills the width.
    var growsHitArea: Bool { self == .control }
}

/// The one press treatment in the app: squeeze (or wash), a touch of dimming, and — for small
/// controls — a hit area grown to 44 pt without the control itself growing.
///
/// There is deliberately **no haptic on touch-down**. An earlier version fired one, which felt
/// good in isolation and wrong in use: it fired on presses the user dragged away and cancelled,
/// it ticked while a finger rested on a set row before a scroll, and it doubled up with the
/// completion haptic every control already fires (`Haptics.step`, `Haptics.setDone`). What
/// actually makes a control feel instant is the *visual* acknowledgement on touch-down, which
/// this does, plus a Taptic Engine that is already warm when the completion haptic lands —
/// hence the `prepare()` on press rather than a second buzz.
///
/// Reduce Motion drops the scale and keeps the dimming, so the control still visibly answers.
struct DGPressStyle: ButtonStyle {
    var weight: DGPressWeight = .control

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, weight: weight)
    }

    private struct PressBody: View {
        let configuration: Configuration
        let weight: DGPressWeight
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .modifier(DGHitArea(active: weight.growsHitArea))
                .scaleEffect(scale)
                .opacity(configuration.isPressed ? 0.82 : 1)
                .background {
                    if weight.dimsBackground, configuration.isPressed {
                        RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                            .fill(DGColor.ink1.opacity(0.06))
                            .padding(.horizontal, -DGSpace.s2)
                    }
                }
                .animation(DGMotion.aware(DGMotion.tap, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    // Arm the engine for whatever haptic the action itself fires. Cold, the
                    // first tap of a session feels late; this costs nothing and fixes that.
                    if pressed, isEnabled { Haptics.warm() }
                }
        }

        private var scale: CGFloat {
            guard configuration.isPressed, !reduceMotion else { return 1 }
            return weight.scale
        }
    }
}

/// Grows a small control's *hit area* toward 44 pt without growing the control, by measuring
/// what it draws and spilling the shortfall outwards as negative padding.
///
/// Two things this has to get right, both learned the hard way:
/// - It must be applied to the button's **label**, inside the `ButtonStyle`. Applied to the
///   `Button` from outside, the padding and `contentShape` land on an ancestor and SwiftUI
///   still hit-tests the button against its own bounds — the whole thing silently does nothing.
/// - Horizontal spill is capped. A set row packs several 28 pt controls with an 8 pt gap; an
///   uncapped grow would have each one reach 8 pt outward, overlapping its neighbour's area so
///   the later sibling wins the gap and the wrong control responds. Vertical space in a row is
///   free, so the full grow happens there and the cap only bites sideways.
private struct DGHitArea: ViewModifier {
    let active: Bool
    var minimum: CGFloat = 44
    /// Half of `DGSpace.s2`, the tightest gap these controls sit in.
    var maxHorizontalSpill: CGFloat = 4
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        if active {
            content
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { size = geo.size }
                            .onChange(of: geo.size) { _, new in size = new }
                    }
                }
                .padding(.horizontal, horizontal)
                .padding(.vertical, vertical)
                .contentShape(Rectangle())
                .padding(.horizontal, -horizontal)
                .padding(.vertical, -vertical)
        } else {
            content.contentShape(Rectangle())
        }
    }

    private var horizontal: CGFloat { min(spill(size.width), maxHorizontalSpill) }
    private var vertical: CGFloat { spill(size.height) }

    private func spill(_ drawn: CGFloat) -> CGFloat {
        guard drawn > 0, drawn < minimum else { return 0 }
        return (minimum - drawn) / 2
    }
}

extension ButtonStyle where Self == DGPressStyle {
    /// Pills, chips, icon buttons, keys. Small ones get their hit area grown to 44 pt.
    static var dgControl: DGPressStyle { DGPressStyle(weight: .control) }
    /// Cards and tiles that fill the width.
    static var dgCard: DGPressStyle { DGPressStyle(weight: .card) }
    /// List and set rows.
    static var dgRow: DGPressStyle { DGPressStyle(weight: .row) }
}

extension View {
    /// Arms the Taptic Engine when a screen that is about to take taps appears, so the
    /// first tap on it feels the same as the tenth.
    func dgWarmHaptics() -> some View {
        onAppear { Haptics.warm() }
    }
}
