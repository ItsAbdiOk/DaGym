import GymCore
import SwiftUI

/// "Showing what's in Home · 212 hidden by equipment, 14 by machine · Show all" — the
/// equipment-profile filter's banner, shared by the library and the exercise picker. Tapping the
/// trailing word flips the filter.
struct EquipmentFilterBanner: View {
    var profileName: String
    var hidden = HiddenCounts()
    @Binding var showingAll: Bool

    /// "Showing what's in Home" plus how many rows the profile hides, split by the reason.
    static func title(profileName: String, hidden: HiddenCounts, showingAll: Bool) -> String {
        if showingAll { return "Showing all equipment" }
        var parts: [String] = []
        if hidden.byType > 0 { parts.append("\(hidden.byType) by equipment") }
        if hidden.byMachine > 0 { parts.append("\(hidden.byMachine) by machine") }
        guard !parts.isEmpty else { return "Showing what's in \(profileName)" }
        return "Showing what's in \(profileName) · hiding \(parts.joined(separator: ", "))"
    }

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.ink3)
                .accessibilityHidden(true)
            Text(Self.title(profileName: profileName, hidden: hidden, showingAll: showingAll))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink2)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text("·").font(DGFont.footnote).foregroundStyle(DGColor.ink4).accessibilityHidden(true)
            Button(showingAll ? "Only \(profileName)" : "Show all") { showingAll.toggle() }
                .buttonStyle(.dgControl)
                .font(DGFont.footnote.weight(.semibold))
                .foregroundStyle(DGColor.coralText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: 36)
        .dgGlass(.thin, radius: 12)
    }
}

/// One 72 pt row in the library list.
struct LibraryRow: View {
    var exercise: ExerciseInfo
    var onToggleFavorite: () -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            HStack(spacing: DGSpace.s3) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(DGFont.title3)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                        .lineLimit(1)
                    Text(exercise.muscleLine)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .lineLimit(1)
                }
                Spacer()
                accessory
            }
            .accessibilityElement(children: .combine)
            favoriteButton
        }
        .frame(minHeight: 72)
        .dgCard(radius: 14, padding: 12)
    }

    private var thumbnail: some View {
        BodyMapView(
            side: BodyMapMuscleMapping.thumbnailSide(forPrimary: exercise.primary),
            intensity: exercise.hitMap
        )
            .padding(6)
            .frame(width: 44, height: 44)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    /// Every row can be (un)favourited from the list, whether or not it has a lift on record.
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: exercise.isFavorite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(exercise.isFavorite ? DGColor.prGoldText : DGColor.ink4)
                .frame(width: 28, height: 28)
                .background(
                    exercise.isFavorite ? DGColor.prGold.opacity(0.18) : DGColor.surface2, in: Circle()
                )
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(exercise.isFavorite ? "Remove from favourites" : "Add to favourites")
    }

    @ViewBuilder
    private var accessory: some View {
        if let best = exercise.bestE1RM {
            VStack(alignment: .trailing, spacing: 2) {
                Text(preferences.formatWeight(kg: best))
                    .dgMetric(DGFont.metricM, tracking: -0.5)
                    .foregroundStyle(DGColor.prGoldText)
                Text("E1RM").dgLabel()
            }
        } else if exercise.loggingStyle == .weightedBodyweight {
            DGTag(text: "BW+", tint: DGColor.infoText, wash: DGColor.info.opacity(0.16))
        } else if exercise.isCustom {
            DGTag(text: "Mine", tint: DGColor.coralText, wash: DGColor.coralWash)
        }
    }
}
