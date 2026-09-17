import GymCore
import SwiftUI

/// Latest bodyweight + change vs 30 days ago as a half-width tile, tapping through to
/// `BodyView` (OpenGym parity 50). With a goal set on the Body tab (`Preferences.bodyweightGoalKg`)
/// the bottom line adds "· 2.1 to go" and is coloured by whether the month moved toward the
/// goal; without one it is just the delta. Health-derived readings are only ever read here.
struct BodyweightTile: View {
    var kg: Double?
    var deltaKg: Double?
    var onTap: () -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Bodyweight").dgLabel()
                    Spacer(minLength: 0)
                    HomeChevron()
                }
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(kg.map { preferences.formatWeight(kg: $0) } ?? "—")
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(DGColor.ink1)
                    if kg != nil {
                        Text(preferences.unitSymbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DGColor.ink3)
                    }
                }
                .padding(.top, 9)
                Text(kg == nil ? emptyText : compactLine)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(kg == nil ? DGColor.ink3 : lineColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 11)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dgCard(radius: 20, padding: 15)
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens Body")
        .accessibilityIdentifier(A11yID.homeBodyweightTile)
    }

    /// "−1.2 · 2.1 to go": the signed 30-day change, then the goal line when there is one.
    private var compactLine: String {
        var parts: [String] = []
        if let deltaKg, abs(deltaKg) >= BodyweightGoal.flatThresholdKg {
            let sign = deltaKg > 0 ? "+" : "−"
            parts.append("\(sign)\(preferences.formatWeight(kg: abs(deltaKg)))")
        } else if deltaKg != nil {
            parts.append("No change")
        }
        if let goalLine { parts.append(goalLine.text) }
        return parts.isEmpty ? "Latest reading" : parts.joined(separator: " · ")
    }

    // MARK: Goal

    private var status: BodyweightGoal.Status? {
        Self.status(kg: kg, deltaKg: deltaKg, preferences: preferences)
    }

    private var goalLine: (text: String, isCelebratory: Bool)? {
        Self.goalLine(kg: kg, deltaKg: deltaKg, preferences: preferences)
    }

    /// Green the month the goal lands or while the change heads toward it; otherwise ink.
    private var lineColor: Color {
        goalLine?.isCelebratory == true ? DGColor.success : deltaColor
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
        guard let goalKg = preferences.bodyweightGoalKg else { return "Log your weight" }
        return "Goal \(preferences.formatWeight(kg: goalKg)) \(preferences.unitSymbol)"
    }

    private var deltaText: String {
        guard let deltaKg, abs(deltaKg) >= BodyweightGoal.flatThresholdKg else {
            return "No change in 30 days"
        }
        let magnitude = preferences.formatWeight(kg: abs(deltaKg))
        let sign = deltaKg > 0 ? "+" : "-"
        return "\(sign)\(magnitude) \(preferences.unitSymbol) vs 30 days ago"
    }

    /// The redesign keeps the month's change in neutral ink whichever way it moved — the sign
    /// says it, and only reaching the goal (`isCelebratory`) earns a colour.
    private var deltaColor: Color { DGColor.ink3 }

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
        HStack(spacing: 10) {
            BodyweightTile(kg: 82.1, deltaKg: -1.4, onTap: {})
            BodyweightTile(kg: 80.1, deltaKg: -1.4, onTap: {})
        }
        HStack(spacing: 10) {
            BodyweightTile(kg: 80, deltaKg: 0, onTap: {})
            BodyweightTile(kg: nil, deltaKg: nil, onTap: {})
        }
    }
    .padding()
    .background(AmbientWash())
    .environment(preferences)
}
