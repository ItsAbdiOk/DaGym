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
}

/// The one press treatment in the app: squeeze (or wash), a touch of dimming, and a soft
/// haptic the instant the finger lands rather than when the action completes.
///
/// The haptic fires on touch-*down*, not on the action, because that is what makes a control
/// feel instant even when the work behind it takes a frame or two. Reduce Motion drops the
/// scale and keeps the dimming, so the control still visibly acknowledges the touch.
struct DGPressStyle: ButtonStyle {
    var weight: DGPressWeight = .control
    /// Set false for controls that fire their own, louder haptic on touch-down.
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, weight: weight, haptic: haptic)
    }

    private struct PressBody: View {
        let configuration: Configuration
        let weight: DGPressWeight
        let haptic: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(scale)
                .opacity(configuration.isPressed ? 0.82 : 1)
                .background {
                    if weight.dimsBackground, configuration.isPressed {
                        RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                            .fill(DGColor.ink1.opacity(0.06))
                            .padding(.horizontal, -DGSpace.s2)
                    }
                }
                .contentShape(Rectangle())
                .animation(DGMotion.aware(DGMotion.tap, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    guard pressed, haptic, isEnabled else { return }
                    Haptics.press()
                }
        }

        private var scale: CGFloat {
            guard configuration.isPressed, !reduceMotion else { return 1 }
            return weight.scale
        }
    }
}

extension ButtonStyle where Self == DGPressStyle {
    /// Pills, chips, icon buttons, keys.
    static var dgControl: DGPressStyle { DGPressStyle(weight: .control) }
    /// Cards and tiles that fill the width.
    static var dgCard: DGPressStyle { DGPressStyle(weight: .card) }
    /// List and set rows.
    static var dgRow: DGPressStyle { DGPressStyle(weight: .row) }
    /// A control that fires its own haptic on touch-down — visual press only.
    static var dgSilent: DGPressStyle { DGPressStyle(weight: .control, haptic: false) }
}

/// Grows a control's *hit area* to 44 pt without growing the control, by measuring what it
/// draws and spilling the shortfall outwards as negative padding. Sizing the frame instead
/// would shove neighbours apart — which is wrong in a dense row like a set row, where a
/// 28 pt stepper has to stay 28 pt and still be comfortably tappable.
private struct DGTapTarget: ViewModifier {
    let minimum: CGFloat
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.onAppear { size = geo.size }
                        .onChange(of: geo.size) { _, new in size = new }
                }
            }
            .padding(.horizontal, inset(size.width))
            .padding(.vertical, inset(size.height))
            .contentShape(Rectangle())
            .padding(.horizontal, -inset(size.width))
            .padding(.vertical, -inset(size.height))
    }

    private func inset(_ drawn: CGFloat) -> CGFloat {
        guard drawn > 0, drawn < minimum else { return 0 }
        return (minimum - drawn) / 2
    }
}

extension View {
    /// Guarantees a 44 × 44 pt hit area around a small control and makes the whole of it
    /// tappable, so no part of a glyph or label is a dead spot. Layout is unchanged: the
    /// control keeps the size it drew at.
    func dgTapTarget(minimum: CGFloat = 44) -> some View {
        modifier(DGTapTarget(minimum: minimum))
    }

    /// Arms the Taptic Engine when a screen that is about to take taps appears, so the
    /// first tap on it feels the same as the tenth.
    func dgWarmHaptics() -> some View {
        onAppear { Haptics.warm() }
    }
}
