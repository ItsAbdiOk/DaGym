import GymCore
import SwiftUI

/// Workout Summary — "Push A Done". Stat tiles, a PR card, muscles hit,
/// a coach debrief, and a share action.
struct WorkoutSummaryView: View {
    var session: WorkoutSession
    var onShare: () -> Void
    var onDone: () -> Void

    var body: some View {
        ZStack {
            AmbientWash(heat: 0.9)
            ScrollView {
                VStack(spacing: DGSpace.s6) {
                    header
                    statRow
                    PRCard()
                    MusclesHitCard(session: session)
                    CoachDebriefCard()
                    actionRow
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
    }

    private var header: some View {
        VStack(spacing: DGSpace.s1) {
            Text("Saturday · 18:24–19:16").dgLabel()
            Text("Push A Done")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
        }
        .frame(maxWidth: .infinity)
    }

    private var statRow: some View {
        HStack(spacing: DGSpace.s3) {
            StatTile(value: "52:04", label: "Time").dgCard(radius: 14)
            StatTile(value: Self.thousands(session.volumeKg), label: "Volume").dgCard(radius: 14)
            StatTile(value: "\(max(session.setsDone, 18))", label: "Sets").dgCard(radius: 14)
        }
    }

    private var actionRow: some View {
        HStack(spacing: DGSpace.s3) {
            DGPrimaryButton(title: "Share Image", symbol: "square.and.arrow.up", action: onShare)
            Button(action: onDone) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .frame(width: 52, height: 52)
                    .dgGlass(.regular, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
            }
            .buttonStyle(DGPressStyle())
        }
    }

    /// Integer kg with a thin-space thousands separator, e.g. "6 840".
    private static func thousands(_ kg: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"
        formatter.maximumFractionDigits = 0
        let value = kg > 0 ? kg : 6840
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

/// Gold-outlined "2 personal records" card.
private struct PRCard: View {
    var body: some View {
        HStack(spacing: DGSpace.s3) {
            RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                .fill(DGColor.prGold)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("2 Personal Records")
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.prGoldText)
                Text("Bench 82.5 × 8 (e1RM 102.5) · Overhead Press 47.5 × 6")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DGColor.prGold.opacity(0.10),
            in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.prGold.opacity(0.4), lineWidth: 1)
        }
    }
}

/// Body map + a two-line breakdown of sets per muscle.
private struct MusclesHitCard: View {
    var session: WorkoutSession

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s4) {
            BodyMapPair(intensity: session.musclesHit, height: 96)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Muscles Hit").dgLabel()
                Text("Chest 9 sets")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                Text("Triceps 6 · Front delts 5")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer(minLength: 0)
        }
        .dgCard()
    }
}

/// Violet coach debrief card.
private struct CoachDebriefCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Coach Debrief · 8/10").dgLabel(DGColor.aiVioletText)
            Text(
                "Strong session. Bench moved up and effort stayed where you wanted it. Watch the last "
                    + "AMRAP — reps dropped from 11 to 8, which usually means the earlier sets were "
                    + "heavier than planned."
            )
            .font(DGFont.body)
            .foregroundStyle(DGColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DGColor.aiViolet.opacity(0.12),
            in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.aiViolet.opacity(0.3), lineWidth: 1)
        }
    }
}

#Preview {
    WorkoutSummaryView(session: SampleData.makeSession(), onShare: {}, onDone: {})
}
