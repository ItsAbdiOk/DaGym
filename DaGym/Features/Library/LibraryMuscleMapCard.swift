import GymCore
import SwiftUI

/// "Explore by muscle": the front and back body maps tinted by how many exercises each muscle
/// has under the current filters (search, equipment chip, favourites, the equipment profile),
/// so a tap on a region is a tap on that muscle's chip. A muscle with no exercise draws inert
/// and takes no tap; `counts` is `LibraryFacets.Remaining.muscleCounts`, already computed
/// for the chips, so the map costs no extra pass.
struct LibraryMuscleMapCard: View {
    var counts: [Muscle: Int]
    var selected: Muscle?
    @Binding var includeSecondary: Bool
    var onSelect: (Muscle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(spacing: DGSpace.s4) {
                map(.front)
                map(.back)
            }
            .frame(height: 220)
            Text(caption)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .accessibilityIdentifier(A11yID.libraryMuscleMapCaption)
            Toggle("Include secondary muscles", isOn: $includeSecondary)
                .font(DGFont.footnote)
                .tint(DGColor.coral)
                .accessibilityIdentifier(A11yID.libraryIncludeSecondary)
        }
        .dgCard()
    }

    private func map(_ side: BodyMapView.Side) -> some View {
        BodyMapView(
            side: side, intensity: LibraryFacets.mapIntensity(counts: counts), onTap: onSelect,
            regionLabel: { muscle, _ in Self.regionLabel(muscle: muscle, count: counts[muscle] ?? 0) }
        )
    }

    /// "Chest · 112 exercises" for the selected muscle, otherwise a nudge — or, when the
    /// filters leave nothing, why the whole figure is inert.
    private var caption: String {
        if let selected {
            return Self.regionLabel(muscle: selected, count: counts[selected] ?? 0)
        }
        return counts.isEmpty
            ? "No exercises match the current filters."
            : "Tap a muscle to see its exercises. Darker means more to choose from."
    }

    /// "Chest, 112 exercises" — the caption and the VoiceOver label share it, so a comma, not
    /// a middle dot, which VoiceOver would skip.
    static func regionLabel(muscle: Muscle, count: Int) -> String {
        "\(muscle.displayName), \(count) \(count == 1 ? "exercise" : "exercises")"
    }
}
