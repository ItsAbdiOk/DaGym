import SwiftUI

/// The three faces of the Train tab. Raw values are the segment labels.
enum TrainSegment: String, CaseIterable, Identifiable {
    case routines = "Routines"
    case programs = "Programs"
    case schedule = "Schedule"

    var id: String { rawValue }
}

/// The prototype's three-way switch under the "Train" title: a low ink track, the selected
/// segment a white pill with a soft shadow. Not `Picker(.segmented)` — the system control tints
/// the pill with the accent and squares the corners, neither of which matches the design.
struct TrainSegmentControl: View {
    @Binding var selection: TrainSegment
    @Namespace private var pill
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrainSegment.allCases) { segment in
                Button {
                    withAnimation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion)) {
                        selection = segment
                    }
                } label: {
                    Text(segment.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 32)
                        .background {
                            if selection == segment {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(scheme == .dark ? Color.white.opacity(0.16) : .white)
                                    .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dgRow)
                .accessibilityAddTraits(selection == segment ? .isSelected : [])
                .accessibilityIdentifier(A11yID.trainSegment(segment.rawValue))
            }
        }
        .padding(3)
        .background(DGColor.ink1.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Train section")
    }
}

/// The prototype's white row group: rows stacked on a 0.72 white fill with a bright half-point
/// edge and hairlines between rows. Dark mode drops to a low white so the wash shows through.
struct TrainRowGroup<Content: View>: View {
    var radius: CGFloat = 14
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(spacing: 0) { content }
            .background(Color.white.opacity(scheme == .dark ? 0.07 : 0.72), in: shape)
            .overlay { shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.9), lineWidth: 0.5) }
            .clipShape(shape)
    }
}

/// The hairline under a row in a `TrainRowGroup`; the last row passes `isLast` to skip it.
struct TrainRowDivider: ViewModifier {
    var isLast: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(DGColor.hairline).frame(height: 0.5).padding(.leading, 15)
            }
        }
    }
}

extension View {
    func trainRowDivider(isLast: Bool) -> some View { modifier(TrainRowDivider(isLast: isLast)) }
}

/// The dim chevron at the trailing edge of a pushing row.
struct TrainChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DGColor.ink4)
            .accessibilityHidden(true)
    }
}

/// The prototype's quiet full-width button inside a card ("Stop", "Share"): 13/600 ink on a
/// 5.5 % ink wash, radius 12.
struct TrainQuietButton: View {
    var title: String
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(role == .destructive ? DGColor.danger : DGColor.ink1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background(
                    DGColor.ink1.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.dgControl)
    }
}

/// The dashed-outline full-width button ("New routine"): 13.5/600 on a 22 % ink dash, radius 18.
struct TrainDashedButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DGColor.ink3)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            DGColor.ink1.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.dgCard)
    }
}
