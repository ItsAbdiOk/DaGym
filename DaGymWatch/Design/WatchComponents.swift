import SwiftUI

/// Full-bleed 50 pt capsule: the one primary control per screen. `tint` is coral for action,
/// green for commit, indigo for voice; `.hollow` draws a text-style button on a card for the
/// "doesn't count" warm-up.
struct CapsuleButton: View {
    enum Style { case filled, hollow }

    var title: String
    var tint: Color = WatchColor.accent
    var style: Style = .filled
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WatchFont.button)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(style == .filled ? Color.black : tint)
                .frame(maxWidth: .infinity, minHeight: WatchMetric.capsule, maxHeight: WatchMetric.capsule)
                .background(
                    Capsule().fill(style == .filled ? tint : WatchColor.card)
                )
                .overlay(
                    Capsule().strokeBorder(style == .hollow ? tint.opacity(0.6) : .clear, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

/// 46 pt list row with the count right-aligned (Home 1B).
struct ListRow: View {
    var title: String
    var trailing: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(WatchFont.bodyMedium).foregroundStyle(WatchColor.ink).lineLimit(1)
                Spacer(minLength: 8)
                Text(trailing).font(WatchFont.body).foregroundStyle(WatchColor.inkSecondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: WatchMetric.listRow, maxHeight: WatchMetric.listRow)
            .background(RoundedRectangle(cornerRadius: WatchMetric.cardRadius).fill(WatchColor.card))
            .contentShape(RoundedRectangle(cornerRadius: WatchMetric.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

/// Set progress: one dot per counting set, filled once done. Collapses to "2 of 4 sets done"
/// for VoiceOver.
struct ProgressDots: View {
    var done: Int
    var total: Int
    var tint: Color = WatchColor.accent

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                Circle()
                    .fill(index < done ? tint : WatchColor.separator)
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) sets done")
    }
}

/// A short line, centred and capped at 150 pt, for the first and last 24 pt safe bands where
/// the screen curves.
struct SafeBandText: View {
    var text: String
    var font: Font = WatchFont.secondary
    var color: Color = WatchColor.inkSecondary
    var maxWidth: CGFloat = WatchMetric.safeBandMaxWidth

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .frame(height: WatchMetric.safeBand)
    }
}

/// Coral progress ring, 9 pt live / 6 pt in always-on. Same geometry both ways.
struct RingView: View {
    var progress: Double
    var lineWidth: CGFloat = 9
    var tint: Color = WatchColor.accent

    var body: some View {
        ZStack {
            Circle().stroke(WatchColor.separator, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
