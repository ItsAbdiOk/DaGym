import GymCore
import SwiftUI

/// Scale-0.97 press, 110 ms — for rows and keys.
struct DGPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DGMotion.tap, value: configuration.isPressed)
    }
}

/// Solid coral pill. The one "act now" control on a screen.
struct DGPrimaryButton: View {
    var title: String
    var symbol: String?
    var fill: Color = DGColor.coral
    var ink: Color = DGColor.inkOnCoral
    var height: CGFloat = 52
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DGSpace.s2) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                }
                Text(title)
                    .font(DGFont.condensedLabel(15))
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fill, in: Capsule())
            .shadow(color: fill.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(DGPressStyle())
    }
}

/// Glass pill with an SF Symbol (44 pt floor). Icon-only, so callers must pass
/// `accessibilityLabel` describing the action (e.g. "Settings", "Add exercise").
struct DGIconButton: View {
    var symbol: String
    var size: CGFloat = 44
    var tint: Color = DGColor.ink1
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .dgGlass(.regular, in: Circle())
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Filter / option chip. Selected = solid coral.
struct DGChip: View {
    var title: String
    var selected = false
    var selectedFill: Color = DGColor.coral
    var selectedInk: Color = DGColor.inkOnCoral
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DGFont.condensedLabel(12))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(selected ? selectedInk : DGColor.ink2)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background {
                    if selected {
                        Capsule().fill(selectedFill)
                    } else {
                        Capsule().fill(DGColor.surface2)
                            .overlay(Capsule().strokeBorder(DGColor.hairline))
                    }
                }
        }
        .buttonStyle(DGPressStyle())
    }
}

/// Small rounded tag, e.g. "3 × 6–8", "RPE 8", "BW+".
struct DGTag: View {
    var text: String
    var tint: Color = DGColor.ink2
    var wash: Color = DGColor.surface3

    var body: some View {
        Text(text)
            .font(DGFont.condensedLabel(11))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(wash, in: RoundedRectangle(cornerRadius: DGRadius.chip, style: .continuous))
    }
}

/// The 28 pt set-type badge at the start of a set row.
struct SetKindBadge: View {
    var kind: SetKind
    var index: Int

    var body: some View {
        Text(kind == .working ? String(index) : kind.badge)
            .font(DGFont.condensedLabel(12))
            .foregroundStyle(kind == .working ? DGColor.ink1 : DGColor.inkOnCoral.opacity(0.9))
            .frame(width: 28, height: 28)
            .background(kind.color, in: RoundedRectangle(cornerRadius: DGRadius.chip, style: .continuous))
    }
}

extension SetKind {
    var color: Color {
        switch self {
        case .warmup: DGColor.setWarmup
        case .working: DGColor.surface3
        case .amrap: DGColor.setAmrap
        case .drop: DGColor.setDrop
        case .failure: DGColor.setFailure
        case .restPause: DGColor.setRestPause
        }
    }
}

extension Effort {
    var color: Color {
        [DGColor.rpeEasy, DGColor.rpeModerate, DGColor.rpeHard, DGColor.rpeVeryHard, DGColor.rpeMax][level]
    }
}

/// Micro label + big number tile ("4 280 / KG VOLUME").
struct StatTile: View {
    var value: String
    var label: String
    var tint: Color = DGColor.ink1

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .dgMetric(DGFont.metricM, tracking: -0.5)
                .foregroundStyle(tint)
            Text(label).dgLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DGSpace.s3)
    }
}

/// "WHY 82.5 KG?" — violet coach card. Never blocks the flow.
struct WhyCard: View {
    var title: String
    var message: String
    var primary: String?
    var secondary: String?
    /// Label tint — violet (default) reads "coach explained this"; pass `DGColor.warning` for a
    /// deload back-off (`GymCore.PrescriptionReason.Kind.deload`) so it reads as a heads-up
    /// rather than routine coaching.
    var labelColor: Color = DGColor.aiVioletText
    var onPrimary: (() -> Void)?
    var onSecondary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(title).dgLabel(labelColor)
            Text(message)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if primary != nil || secondary != nil {
                HStack(spacing: DGSpace.s2) {
                    if let primary {
                        Button(primary) { onPrimary?() }
                            .buttonStyle(.plain)
                            .font(DGFont.condensedLabel(13))
                            .textCase(.uppercase)
                            .foregroundStyle(DGColor.inkOnCoral)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(DGColor.aiViolet, in: Capsule())
                    }
                    if let secondary {
                        Button(secondary) { onSecondary?() }
                            .buttonStyle(.plain)
                            .font(DGFont.condensedLabel(13))
                            .textCase(.uppercase)
                            .foregroundStyle(DGColor.ink2)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(DGColor.surface3, in: Capsule())
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DGColor.aiViolet.opacity(0.12),
            in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.aiViolet.opacity(0.3), lineWidth: 1)
        }
    }
}

/// Names the missing thing, says what unlocks it, offers exactly one action.
struct EmptyState: View {
    var symbol: String?
    var title: String
    var message: String
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        VStack(spacing: DGSpace.s3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DGColor.ink3)
                    .frame(width: 56, height: 56)
                    .background(
                        DGColor.surface3,
                        in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    )
            }
            Text(title)
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text(message)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
                .multilineTextAlignment(.center)
            if let action {
                DGPrimaryButton(title: action) { onAction?() }
                    .padding(.top, DGSpace.s2)
            }
        }
        .frame(maxWidth: .infinity)
        .dgCard(padding: DGSpace.s6)
    }
}

extension DGFont {
    /// Condensed bold at an arbitrary size for buttons, chips and badges. Scales with
    /// Dynamic Type against `.footnote`, the closest built-in style to these sizes.
    static func condensedLabel(_ size: CGFloat) -> Font {
        Font.custom(Family.condensedBold, size: size, relativeTo: .footnote)
    }
}
