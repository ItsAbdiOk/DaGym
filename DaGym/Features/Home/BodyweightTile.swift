import GymCore
import SwiftUI

/// Latest bodyweight + change vs 30 days ago, tapping through to `BodyView` (OpenGym parity 50).
/// With a goal set on the Body tab (`Preferences.bodyweightGoalKg`) the value line adds
/// "· 2.1 to go" and the delta is coloured by whether it moved toward the goal; without one
/// the tile is exactly as before. Health-derived readings are only ever read here.
struct BodyweightTile: View {
    var kg: Double?
    var deltaKg: Double?
    var onTap: () -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DGSpace.s4) {
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text("Bodyweight").dgLabel()
                    if let kg {
                        valueLine(kg: kg)
                        Text(deltaText)
                            .font(DGFont.footnote)
                            .foregroundStyle(deltaColor)
                    } else {
                        Text(emptyText)
                            .font(DGFont.footnote)
                            .foregroundStyle(DGColor.ink3)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
        }
        .buttonStyle(.dgCard)
        .dgCard()
        .accessibilityLabel(accessibilityLabel)
    }

    private func valueLine(kg: Double) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(preferences.formatWeight(kg: kg))
                .dgMetric(DGFont.metricM)
                .foregroundStyle(DGColor.ink1)
            Text(preferences.unitSymbol)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
            if let goalLine {
                Text("· \(goalLine.text)")
                    .font(DGFont.subhead)
                    .foregroundStyle(goalLine.color)
            }
        }
    }

    // MARK: Goal

    private var status: BodyweightGoal.Status? {
        Self.status(kg: kg, deltaKg: deltaKg, preferences: preferences)
    }

    private var goalLine: (text: String, color: Color)? {
        guard let line = Self.goalLine(kg: kg, deltaKg: deltaKg, preferences: preferences) else { return nil }
        return (line.text, line.isCelebratory ? DGColor.success : DGColor.ink3)
    }

    static func status(kg: Double?, deltaKg: Double?, preferences: Preferences) -> BodyweightGoal.Status? {
        guard let kg, let goalKg = preferences.bodyweightGoalKg else { return nil }
        return BodyweightGoal.status(
            currentKg: kg, goalKg: goalKg, deltaKg: deltaKg, unit: preferences.weightUnit
        )
    }

    /// "2.1 to go" while short of the goal; "Goal reached" (celebratory) the month it lands —
    /// the 30-day delta still shows movement; then a quiet "At goal" once the weight has held.
    /// Nil without a goal or a reading. Static so the wording is testable off-screen.
    static func goalLine(
        kg: Double?, deltaKg: Double?, preferences: Preferences
    ) -> (text: String, isCelebratory: Bool)? {
        guard let status = status(kg: kg, deltaKg: deltaKg, preferences: preferences) else { return nil }
        if status.isReached {
            let justReached = deltaKg.map { abs($0) >= BodyweightGoal.flatThresholdKg } ?? false
            return justReached ? ("Goal reached", true) : ("At goal", false)
        }
        return ("\(preferences.formatWeight(kg: status.remainingKg)) to go", false)
    }

    private var emptyText: String {
        guard let goalKg = preferences.bodyweightGoalKg else { return "Log your weight to see it here" }
        let goal = "\(preferences.formatWeight(kg: goalKg)) \(preferences.unitSymbol)"
        return "Log your weight to track it against \(goal)"
    }

    private var deltaText: String {
        guard let deltaKg, abs(deltaKg) >= BodyweightGoal.flatThresholdKg else {
            return "No change in 30 days"
        }
        let magnitude = preferences.formatWeight(kg: abs(deltaKg))
        let sign = deltaKg > 0 ? "+" : "-"
        return "\(sign)\(magnitude) \(preferences.unitSymbol) vs 30 days ago"
    }

    /// Green when the month's change moved toward the goal; otherwise the neutral ink the tile
    /// always used — moving away is not painted red, the number says it.
    private var deltaColor: Color {
        guard let deltaKg, abs(deltaKg) >= BodyweightGoal.flatThresholdKg else { return DGColor.ink4 }
        return status?.trend == .toward ? DGColor.success : DGColor.ink3
    }

    private var accessibilityLabel: String {
        guard let kg else { return "Bodyweight. \(emptyText)" }
        var parts = ["Bodyweight \(preferences.formatWeight(kg: kg)) \(preferences.unitSymbol)"]
        if let goalLine { parts.append(goalLine.text) }
        parts.append(deltaText)
        return parts.joined(separator: ", ")
    }
}

#Preview {
    let preferences = Preferences()
    preferences.bodyweightGoalKg = 80
    return VStack(spacing: DGSpace.s3) {
        BodyweightTile(kg: 82.1, deltaKg: -1.4, onTap: {})
        BodyweightTile(kg: 80.1, deltaKg: -1.4, onTap: {})
        BodyweightTile(kg: 80, deltaKg: 0, onTap: {})
        BodyweightTile(kg: nil, deltaKg: nil, onTap: {})
    }
    .padding()
    .background(AmbientWash())
    .environment(preferences)
}
