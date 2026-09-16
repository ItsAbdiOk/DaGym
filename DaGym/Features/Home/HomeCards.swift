import GymCore
import SwiftUI

/// Home cards that only appear in particular states: the starter-plan picker on an empty store
/// and the sample-data banner (the bodyweight tile is `BodyweightTile.swift`). Split out of
/// `HomeView.swift` to keep both files under the 400-line cap.

struct StarterPlanCard: View {
    var onPick: (StarterProgramKind) -> Void
    var onAskCoach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Get Started").dgLabel(DGColor.coralText)
            Text("Pick a Starter Plan")
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("No routines yet. Ask the coach to build one for you, or choose a program and DaGym "
                + "schedules the rest.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            DGPrimaryButton(
                title: "Ask the Coach", symbol: "bubble.left.and.text.bubble.right", action: onAskCoach
            )
            StarterPlanList(onPick: onPick)
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
