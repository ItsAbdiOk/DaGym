import GymCore
import SwiftUI

/// The smaller Today cards from the redesign: the week tile beside `BodyweightTile`, the
/// recovery row and the tinted deload strip. Each is a `.dgCard(radius: 20)` with the
/// prototype's 15 pt inset rather than the default hero padding.

/// "THIS WEEK · 3 of 4" with one accent segment per workout toward the weekly goal.
struct WeekTile: View {
    var done: Int
    var total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This week").dgLabel()
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(done)")
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                Text("of \(total)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DGColor.ink3)
            }
            .padding(.top, 9)
            HStack(spacing: 4) {
                ForEach(0..<max(total, 1), id: \.self) { index in
                    Capsule()
                        .fill(index < done ? DGColor.coral : DGColor.ink1.opacity(0.14))
                        .frame(height: 5)
                }
            }
            .padding(.top, 11)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dgCard(radius: 20, padding: 15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week, \(done) of \(total) workouts")
    }
}

/// One-line recovery state with a coloured dot, tapping through to the muscle map.
struct RecoveryRow: View {
    var map: [Muscle: Double]
    var onSeeRecovery: () -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var headline: (title: String, body: String) { Recovery.headline(map: map) }

    var body: some View {
        Button(action: onSeeRecovery) {
            HStack(spacing: DGSpace.s3) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                    Text(headline.body)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HomeChevron()
            }
            .dgCard(radius: 20, padding: DGSpace.s4)
        }
        .buttonStyle(DGPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the muscle map")
    }

    /// The most-spent muscle's stop on the recovery ramp, so the dot agrees with the map — and
    /// never greener than the middle stop while the headline says something is "still spent".
    private var dotColor: Color {
        let ramp = DGColor.recoveryRamp(
            differentiateWithoutColor: differentiateWithoutColor,
            colorBlindHeatmaps: preferences.colorBlindHeatmaps
        )
        let spent = map.values.max() ?? 0
        var index = min(ramp.count - 1, max(0, Int(spent * Double(ramp.count))))
        if spent > TrainingConstants.recoveryHeadlineThreshold { index = max(index, ramp.count / 2) }
        return ramp[index]
    }
}

/// The tinted "Deload week suggested" strip: "Plan" builds the deload week, "Not now" snoozes
/// it (`HomeView.snoozeDeload`).
struct DeloadStrip: View {
    var reason: String
    var onPlan: () -> Void
    var onSnooze: () -> Void

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Deload week suggested")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                Text(reason)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Not now", action: onSnooze)
                    .buttonStyle(DGPressStyle())
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DGColor.ink3)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Plan", action: onPlan)
                .buttonStyle(DGPressStyle())
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .padding(.horizontal, 13)
                .frame(minHeight: 34)
                .background(DGColor.surface1, in: Capsule())
                .overlay { Capsule().strokeBorder(DGColor.hairline, lineWidth: 0.5) }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.vertical, 15)
        .background(DGColor.ink1.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DGColor.ink1.opacity(0.08), lineWidth: 0.5)
        }
    }
}

/// The dim trailing chevron every tappable Today row ends with.
struct HomeChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DGColor.ink1.opacity(0.3))
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: DGSpace.s3) {
        HStack(spacing: 10) {
            WeekTile(done: 3, total: 4)
            WeekTile(done: 0, total: 3)
        }
        RecoveryRow(map: [.quads: 0.7, .chest: 0.1], onSeeRecovery: {})
        DeloadStrip(reason: "Bench has stalled three sessions running.", onPlan: {}, onSnooze: {})
    }
    .padding()
    .background(AmbientWash())
    .environment(Preferences())
}
