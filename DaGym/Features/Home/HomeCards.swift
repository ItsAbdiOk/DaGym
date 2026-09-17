import GymCore
import SwiftUI

/// Home cards that only appear in particular states: the starter-plan picker on an empty store
/// and the sample-data banner (the bodyweight tile is `BodyweightTile.swift`). Split out of
/// `HomeView.swift` to keep both files under the 400-line cap.

/// The hero card's empty-store variant: no routines yet, so offer the starter plans, the coach
/// and a freestyle session in one card built to the same recipe as `HomeHeroCard`.
struct StarterPlanCard: View {
    var onPick: (StarterProgramKind) -> Void
    var onAskCoach: () -> Void
    /// A lifter with no routines can still train: the freestyle start keeps `home.start` on the
    /// screen so the first workout never waits on a plan.
    var onFreestyle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeStatusPill(text: "Get started")
            Text("Pick a starter plan")
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(DGColor.ink1)
                .padding(.top, 14)
            Text("No routines yet. Ask the coach to build one for you, or choose a program and DaGym "
                + "schedules the rest.")
                .font(.system(size: 14))
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            StarterPlanList(onPick: onPick)
                .padding(.top, 16)
            HStack(spacing: 10) {
                Button(action: onFreestyle) {
                    Text("Freestyle workout")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(DGColor.coral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: DGColor.coral.opacity(0.3), radius: 10, y: 8)
                }
                .buttonStyle(DGPressStyle())
                .accessibilityIdentifier(A11yID.homeStart)
                Button(action: onAskCoach) {
                    Text("Ask the coach")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                        .padding(.horizontal, DGSpace.s4)
                        .frame(minHeight: 50)
                        .homeSecondaryFill()
                }
                .buttonStyle(DGPressStyle())
            }
            .padding(.top, 18)
        }
        .dgCard(radius: DGRadius.xl)
    }
}

/// "Sample data · Clear" banner while `Preferences.sampleDataMode` is on (OpenGym parity 84).
struct SampleDataBanner: View {
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DGColor.coralText)
                .accessibilityHidden(true)
            Text("Sample data — for exploring the app")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DGColor.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Clear", action: onClear)
                .buttonStyle(DGPressStyle())
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .padding(.horizontal, 13)
                .frame(minHeight: 34)
                .background(DGColor.surface1, in: Capsule())
                .overlay { Capsule().strokeBorder(DGColor.hairline, lineWidth: 0.5) }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.vertical, 10)
        .background(DGColor.ink1.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DGColor.ink1.opacity(0.08), lineWidth: 0.5)
        }
    }
}
