import SwiftUI

/// A three-way switch under a pushed screen's title (This week's Trends / Records /
/// Consistency, the muscle map's Balance / Recovery / Strength): a low ink track, the selected
/// segment a white pill with a soft shadow. Generic over the segment enum so each screen keeps
/// its own type; the Train tab's `TrainSegmentControl` is the same recipe pinned to its enum.
struct ProgressSegmentControl<Segment: CaseIterable & Hashable & Identifiable>: View
where Segment.AllCases: RandomAccessCollection {
    @Binding var selection: Segment
    var title: (Segment) -> String
    var accessibilityID: (Segment) -> String
    var controlLabel: String
    @Namespace private var pill
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Segment.allCases) { segment in
                Button {
                    withAnimation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion)) {
                        selection = segment
                    }
                } label: {
                    Text(title(segment))
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
                .accessibilityIdentifier(accessibilityID(segment))
            }
        }
        .padding(3)
        .background(DGColor.ink1.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controlLabel)
    }
}

/// The prototype's small white stat tile ("184 / Workouts", "Volume / 18.6 t / +8.1%"): value in
/// bold tabular figures, a quiet label, and an optional delta line that goes accent when the
/// week moved the right way.
struct ProgressStatTile: View {
    var value: String
    var label: String
    var delta: String?
    /// Accent for a positive move; ink otherwise (a negative delta is information, not alarm).
    var deltaIsPositive = false
    var centered = true
    /// Keeps the delta line's height even when there is no delta (the This week strip).
    var reservesDeltaLine = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 6) {
            if !centered {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DGColor.ink3)
            }
            Text(value)
                .font(.system(size: centered ? 19 : 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if centered {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DGColor.ink3)
            }
            // A tile with nothing to compare against keeps the delta line, so a row of tiles stays
            // one height.
            if reservesDeltaLine || delta != nil {
                Text(delta ?? " ")
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(deltaIsPositive ? DGColor.coralText : DGColor.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 10)
        .dgCard(radius: 16, padding: 0)
        .accessibilityElement(children: .combine)
    }
}

/// One "icon · title / subtitle · chevron" row in a Progress row group, pushing a destination.
struct ProgressPushRow<Destination: View>: View {
    var symbol: String
    var title: String
    var subtitle: String
    var isLast = false
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink { destination() } label: {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.coral)
                    .frame(width: 34, height: 34)
                    .background(DGColor.coralWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DGColor.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                TrainChevron()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .trainRowDivider(isLast: isLast)
        }
        .buttonStyle(.dgRow)
    }
}

/// A card's 14pt semibold title line, optionally with a trailing caption ("+8.1% vs last week").
struct ProgressCardTitle: View {
    var title: String
    var trailing: String?
    var trailingTint: Color = DGColor.coralText

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(trailingTint)
            }
        }
    }
}
