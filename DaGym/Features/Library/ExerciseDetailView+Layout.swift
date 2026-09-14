import GymCore
import SwiftUI

/// The read-only display pieces of `ExerciseDetailView`'s body — hero art, title, stat tiles and
/// the 1RM row — split out from the main file to stay under the type-body-length cap.
extension ExerciseDetailView {
    var instructionLines: [String] {
        exercise.instructions.isEmpty ? [] : [exercise.instructions]
    }

    var oneRepMaxRow: some View {
        Button {
            showingCalculator = true
        } label: {
            HStack {
                Image(systemName: "function")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DGColor.prGoldText)
                Text("1RM Calculator")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: DGTap.min)
            .dgCard(padding: 0)
        }
        .buttonStyle(.dgRow)
    }

    var topRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: DGSpace.s1) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Library").dgLabel()
                }
                .foregroundStyle(DGColor.ink3)
            }
            .buttonStyle(.dgControl)
            Spacer()
            Button(action: toggleFavorite) {
                Image(systemName: exercise.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.prGoldText)
                    .frame(width: 36, height: 36)
                    .dgGlass(.regular, in: Circle())
            }
            .buttonStyle(.dgControl)
        }
    }

    /// The illustrated 3-frame hero, shown only when this exercise has matching art — no
    /// placeholder or reserved space otherwise, so exercises without art keep today's layout.
    @ViewBuilder
    var heroArt: some View {
        if let seedID = exercise.seedID, ExerciseArtCatalog.frames(for: seedID) != nil {
            VStack(spacing: DGSpace.s2) {
                ExerciseArtView(seedID: seedID, size: 240, animated: true)
                    .accessibilityLabel("Illustration demonstrating \(exercise.name)")
                Text("Illustration: Bryl Lim, derived from Everkinetic · CC BY-SA 4.0")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var titleBlock: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            HStack(alignment: .top) {
                Text(exercise.name)
                    .font(DGFont.title1)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(2)
                Spacer()
                BodyMapPair(intensity: exercise.hitMap, height: 56)
            }
            Text(equipmentLine)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    /// "barbell · olympic bar · 2.5 kg increment"; a bodyweight move has no bar and no
    /// increment worth stating, so it reads just "bodyweight".
    var equipmentLine: String {
        var parts = [exercise.equipment]
        if let bar = exercise.bar { parts.append(bar.name.lowercased()) }
        if exercise.incrementKg > 0 {
            let increment = preferences.formatWeight(kg: exercise.incrementKg)
            parts.append("\(increment) \(preferences.unitSymbol) increment")
        }
        return parts.joined(separator: " · ")
    }

    var statTiles: some View {
        HStack(spacing: DGSpace.s3) {
            goldStat
            StatTile(value: exercise.bestSet ?? "—", label: "Best Set")
                .dgCard(radius: 14, padding: 0)
            StatTile(value: "\(exercise.sessions)", label: "Sessions")
                .dgCard(radius: 14, padding: 0)
        }
    }

    var goldStat: some View {
        StatTile(
            value: exercise.bestE1RM.map { preferences.formatWeight(kg: $0) } ?? "—",
            label: "Best E1RM", tint: DGColor.prGoldText
        )
        .dgCard(
            radius: 14, fill: DGColor.prGold.opacity(0.10), stroke: DGColor.prGold.opacity(0.35), padding: 0
        )
    }
}
