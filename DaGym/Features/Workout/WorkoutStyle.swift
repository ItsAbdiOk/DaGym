import SwiftUI

// The redesign prototype's small surfaces on the workout screens, shared so every card, tile
// and sheet row here is built from the same three recipes.

/// A flat frosted tile (`rgba(255,255,255,.7)` with a bright half-point edge, no shadow): the
/// three stat tiles under the header, the summary's stat tiles, a set row. Lighter than
/// `.dgCard()`, which carries the warm drop shadow reserved for reading cards.
private struct WorkoutTileModifier: ViewModifier {
    var radius: CGFloat
    var opacity: Double
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(.white.opacity(dark ? 0.07 : opacity)))
            .overlay { shape.strokeBorder(.white.opacity(dark ? 0.12 : 0.9), lineWidth: 0.5) }
    }
}

/// The ink-tinted secondary pill ("Add set", "Swap", the keypad's ± keys): `rgba(28,25,23,.055)`.
private struct WorkoutInkPillModifier: ViewModifier {
    var radius: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.background(
            DGColor.ink1.opacity(opacity),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}

extension View {
    func dgTile(radius: CGFloat = 13, opacity: Double = 0.7) -> some View {
        modifier(WorkoutTileModifier(radius: radius, opacity: opacity))
    }

    func dgInkPill(radius: CGFloat = DGRadius.sm, opacity: Double = 0.055) -> some View {
        modifier(WorkoutInkPillModifier(radius: radius, opacity: opacity))
    }
}

/// A full-width secondary button in the prototype's two recipes: a frosted white pill
/// ("Add exercise", "Share card") or an ink-tinted one ("Add set", "Swap").
struct WorkoutPillButton: View {
    enum Style {
        case frosted, ink
    }

    var title: String
    var style: Style = .frosted
    var radius: CGFloat = DGRadius.md
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DGFont.condensedLabel(13.5))
                .foregroundStyle(DGColor.ink1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .modifier(PillBackground(style: style, radius: radius))
        }
        .buttonStyle(.dgControl)
    }

    private struct PillBackground: ViewModifier {
        var style: Style
        var radius: CGFloat

        @ViewBuilder
        func body(content: Content) -> some View {
            switch style {
            case .frosted: content.dgTile(radius: radius, opacity: 0.66)
            case .ink: content.dgInkPill(radius: radius)
            }
        }
    }
}

/// The 30–34 pt round ink-washed icon button from the prototype's header and card corners
/// (chevron, mic, "…"). `DGIconButton` is the glass one for floating chrome; this sits on a
/// frosted surface, where glass on glass would vanish.
struct WorkoutRoundButton: View {
    var symbol: String
    var size: CGFloat = 32
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            WorkoutRoundGlyph(symbol: symbol, size: size)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// `WorkoutRoundButton`'s face, on its own so a `Menu` can wear it as a label.
struct WorkoutRoundGlyph: View {
    var symbol: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(DGColor.ink3)
            .frame(width: size, height: size)
            .background(DGColor.ink1.opacity(0.07), in: Circle())
    }
}

/// A sheet of plain choices — the exercise actions and the swap reasons: a centred title, one
/// white row group with hairlines, and a "Cancel" pill. Rows are plain `Button`s so callers keep
/// their own actions and roles; a destructive row passes `tint: DGColor.danger`.
struct WorkoutChoiceSheet<Rows: View>: View {
    var title: String
    var cancelTitle = "Cancel"
    @ViewBuilder var rows: () -> Rows

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DGSpace.s3) {
            Text(title)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
                .multilineTextAlignment(.center)
                .padding(.top, DGSpace.s2)
            VStack(spacing: 0) { rows() }
                .background(
                    DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                        .strokeBorder(DGColor.hairline, lineWidth: 0.5)
                }
            Button(cancelTitle) { dismiss() }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(15.5))
                .foregroundStyle(DGColor.ink1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .dgInkPill(radius: DGRadius.md, opacity: 0.06)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s4)
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.bgBase)
    }
}

/// One row of a `WorkoutChoiceSheet`: 48 pt, 15.5 pt regular text, hairline underneath.
struct WorkoutChoiceRow: View {
    var title: String
    var tint: Color = DGColor.ink1
    var isLast = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15.5))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
        .overlay(alignment: .bottom) {
            if !isLast { Divider().overlay(DGColor.hairline).padding(.leading, 15) }
        }
    }
}
