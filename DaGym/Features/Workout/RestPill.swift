import SwiftUI

/// Floating glass-thick pill: depleting ring, countdown, next-set label,
/// +30 s and Skip. Sits above the action bar as one sticky group.
struct RestPill: View {
    var remaining: Int
    var total: Int
    /// "Next <exercise name>" / "Last set done" — used as-is when `nextWeightKg`/`nextReps`
    /// are nil; otherwise those raw values are formatted in the user's unit instead.
    var nextLabel: String
    var nextWeightKg: Double?
    var nextReps: Int?
    var onAddThirty: () -> Void
    var onSkip: () -> Void

    @Environment(Preferences.self) private var preferences

    private var resolvedNextLabel: String {
        if let nextWeightKg, let nextReps {
            return "Next \(preferences.formatWeight(kg: nextWeightKg)) × \(nextReps)"
        }
        return nextLabel
    }

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            RestRing(remaining: remaining, total: total, size: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutSession.clock(remaining))
                    .dgMetric(DGFont.metricL)
                    .foregroundStyle(DGColor.ink1)
                Text("Rest · \(resolvedNextLabel)")
                    .dgLabel()
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: DGSpace.s2)
            Button(action: onAddThirty) {
                Text("+30s")
                    .font(DGFont.condensedLabel(12))
                    .foregroundStyle(DGColor.ink1)
                    .frame(width: 44, height: 44)
                    .dgGlass(.regular, in: Circle())
            }
            .buttonStyle(DGPressStyle())
            .accessibilityLabel("Add 30 seconds")
            Button("Skip", action: onSkip)
                .buttonStyle(.plain)
                .font(DGFont.condensedLabel(13))
                .textCase(.uppercase)
                .foregroundStyle(DGColor.inkOnCoral)
                .padding(.horizontal, DGSpace.s4)
                .frame(height: 44)
                .background(DGColor.coral, in: Capsule())
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.vertical, DGSpace.s2)
        .dgGlass(.thick, in: Capsule())
    }
}

/// Compact ring + time only, for the scrolled state.
struct RestPillCompact: View {
    var remaining: Int
    var total: Int

    var body: some View {
        ZStack {
            RestRing(remaining: remaining, total: total, size: 48)
            Text(WorkoutSession.clock(remaining))
                .dgMetric(DGFont.footnote)
                .foregroundStyle(DGColor.ink1)
        }
        .frame(width: 48, height: 48)
        .dgGlass(.thick, in: Circle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rest, \(WorkoutSession.clock(remaining)) remaining")
    }
}

private struct RestRing: View {
    var remaining: Int
    var total: Int
    var size: CGFloat

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(remaining) / Double(total)
    }

    private var isFinal: Bool { remaining > 0 && remaining <= 3 }

    var body: some View {
        ZStack {
            Circle().stroke(DGColor.hairline, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(DGMotion.timer, value: remaining)
    }

    private var ringColor: Color { isFinal ? DGColor.coralPress : DGColor.coral }
}

#Preview {
    VStack(spacing: DGSpace.s4) {
        RestPill(
            remaining: 92, total: 150, nextLabel: "", nextWeightKg: 82.5, nextReps: 8,
            onAddThirty: {}, onSkip: {}
        )
        RestPillCompact(remaining: 2, total: 60)
    }
    .padding()
    .background(DGColor.bgBase)
    .environment(Preferences())
}
