import SwiftUI

/// The hub's hero card: three concentric rings (sessions against the goal, volume against last
/// week, effort on the RPE scale) with a dotted legend on the right.
struct ProgressRingsCard: View {
    var summary: ProgressHubSummary

    @Environment(Preferences.self) private var preferences

    /// The prototype's fixed ring hues: accent, a teal, a gold. Teal and gold are not accent-
    /// aware on purpose — they need to read apart from the accent whichever theme is picked.
    static let volumeTint = Color(hex: 0x2C8F78)
    static let effortTint = Color(hex: 0xB5771C)

    var body: some View {
        // The legend sits beside the rings, or under them at accessibility sizes where the
        // column beside a 140 pt ring broke "SESSIONS" one letter per line.
        DGAdaptiveStack(spacing: 18) {
            rings
            VStack(alignment: .leading, spacing: 14) {
                legend("Sessions", tint: DGColor.coral, value: sessionsText)
                legend("Volume", tint: Self.volumeTint, value: volumeText)
                legend("Effort", tint: Self.effortTint, value: effortText)
            }
            Spacer(minLength: 0)
        }
        .dgCard(radius: DGRadius.xl)
        .accessibilityElement(children: .combine)
    }

    private var sessionsText: String { "\(summary.thisWeekCount) / \(summary.weeklyGoal)" }

    private var volumeText: String {
        "\(preferences.formatVolume(kg: summary.volumeKg)) \(preferences.unitSymbol)"
    }

    private var effortText: String {
        guard let rpe = summary.meanRPE else { return "—" }
        let scale = preferences.effortScale == .rir ? "RIR" : "RPE"
        let value = preferences.effortScale == .rir ? 10 - rpe : rpe
        return "\(scale) \(String(format: "%.1f", value))"
    }

    private var rings: some View {
        ZStack {
            ring(radius: 60, fraction: summary.sessionsFraction, tint: DGColor.coral)
            ring(radius: 45, fraction: summary.volumeFraction, tint: Self.volumeTint)
            ring(radius: 30, fraction: summary.effortFraction, tint: Self.effortTint)
        }
        .frame(width: 140, height: 140)
        .accessibilityHidden(true)
    }

    private func ring(radius: CGFloat, fraction: Double, tint: Color) -> some View {
        ZStack {
            Circle().stroke(DGColor.ink1.opacity(0.1), lineWidth: 13)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    private func legend(_ label: String, tint: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 9, height: 9)
                Text(label).dgLabel()
            }
            Text(value)
                .font(.system(size: 21, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
