import GymCore
import SwiftUI

/// Home cards that only appear in particular states: the starter-plan picker on an empty store,
/// the sample-data banner, and the bodyweight tile. Split out of `HomeView.swift` to keep both
/// files under the 400-line cap.

struct StarterPlanCard: View {
    var onPick: (StarterProgramKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Get Started").dgLabel(DGColor.coralText)
            Text("Pick a Starter Plan")
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("No routines yet. Choose a program and DaGym schedules the rest.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            VStack(spacing: DGSpace.s2) {
                ForEach(StarterProgramKind.allCases) { kind in
                    Button { onPick(kind) } label: {
                        HStack {
                            Text(kind.rawValue).font(DGFont.body).foregroundStyle(DGColor.ink1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DGColor.ink4)
                        }
                        .padding(.horizontal, DGSpace.s4)
                        .frame(minHeight: 48)
                        .background(
                            DGColor.surface1,
                            in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                        )
                    }
                    .buttonStyle(.dgRow)
                }
            }
        }
        .padding(DGSpace.s5)
        .background(DGColor.coralWash, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.coral, lineWidth: 1)
        }
    }
}

/// "Sample data · Clear" banner while `Preferences.sampleDataMode` is on (OpenGym parity 84).
struct SampleDataBanner: View {
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Image(systemName: "sparkles")
                .foregroundStyle(DGColor.infoText)
            Text("Sample data — for exploring the app")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink2)
            Spacer()
            Button("Clear", action: onClear)
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(12))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.coralText)
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: 44)
        .background(
            DGColor.info.opacity(0.10), in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
        )
    }
}

/// Latest bodyweight + change vs 30 days ago, tapping through to `BodyView` (OpenGym parity 50).
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
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(preferences.formatWeight(kg: kg))
                                .dgMetric(DGFont.metricM)
                                .foregroundStyle(DGColor.ink1)
                            Text(preferences.unitSymbol)
                                .font(DGFont.subhead)
                                .foregroundStyle(DGColor.ink3)
                        }
                        Text(deltaText)
                            .font(DGFont.footnote)
                            .foregroundStyle(deltaColor)
                    } else {
                        Text("Log your weight to see it here")
                            .font(DGFont.footnote)
                            .foregroundStyle(DGColor.ink3)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
        }
        .buttonStyle(.dgCard)
        .dgCard()
    }

    private var deltaText: String {
        guard let deltaKg, abs(deltaKg) >= 0.1 else { return "No change in 30 days" }
        let magnitude = preferences.formatWeight(kg: abs(deltaKg))
        let sign = deltaKg > 0 ? "+" : "-"
        return "\(sign)\(magnitude) \(preferences.unitSymbol) vs 30 days ago"
    }

    private var deltaColor: Color {
        guard let deltaKg, abs(deltaKg) >= 0.1 else { return DGColor.ink4 }
        return DGColor.ink3
    }
}

/// Half-width "3 / 4" weekly goal card with a segmented progress bar.
