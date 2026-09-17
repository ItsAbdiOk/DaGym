import SwiftUI

/// Settings › Display: the accent swatches and appearance, then the screen-awake, photo-lock
/// and colour-blind-heatmap toggles, then the body figure (plan.md Phase 8).
struct DisplaySettingsSection: View {
    /// The design's swatch order: terracotta first, ink last.
    static let swatchOrder: [DGAccent] = [.coral, .ice, .lime, .violet, .ember]

    @Environment(Preferences.self) private var preferences

    var body: some View {
        SettingsSection {
            accentRow
            SettingsDivider()
            SettingsRow(label: "Appearance") {
                SettingsSegment(
                    label: "Appearance", selection: appearanceBinding,
                    options: [
                        (Preferences.Appearance.system, "System"), (.light, "Light"), (.dark, "Dark")
                    ]
                )
            }
        }
        SettingsSection {
            SettingsToggleRow(label: "Keep screen awake", isOn: keepScreenAwakeBinding)
            SettingsDivider()
            SettingsToggleRow(label: "Lock progress photos", isOn: lockPhotosBinding)
            SettingsDivider()
            SettingsToggleRow(
                label: "Colour-blind heatmaps",
                sub: "Swaps the recovery map and consistency calendar to a scale that avoids red vs. green.",
                isOn: colorBlindHeatmapsBinding
            )
        }
        SettingsSection(
            note: "Picks the figure the muscle map draws. Neutral uses the same regions on the "
                + "male outline."
        ) {
            SettingsRow(label: "Body figure") {
                SettingsSegment(
                    label: "Body figure", selection: bodyFigureBinding,
                    options: [
                        (Preferences.BodyFigure.neutral, "Neutral"), (.male, "Male"), (.female, "Female")
                    ]
                )
            }
        }
    }

    /// Five accent swatches. Tapping one sets `Preferences.accent`, which updates
    /// `DGColor.current` synchronously — this row (and every other coral-tinted control still on
    /// screen) re-renders the moment `preferences.accent` changes, since it reads that property
    /// directly below.
    private var accentRow: some View {
        SettingsRow(label: "Accent") {
            HStack(spacing: DGSpace.s2) {
                ForEach(Self.swatchOrder, id: \.self) { accent in
                    AccentSwatch(accent: accent, isSelected: preferences.accent == accent) {
                        preferences.accent = accent
                    }
                }
            }
        }
    }

    /// System/Light/Dark, applied by whatever reads `preferences.appearance.colorScheme` further
    /// up the view hierarchy (`preferredColorScheme`) — this row only writes the preference.
    private var appearanceBinding: Binding<Preferences.Appearance> {
        Binding(get: { preferences.appearance }, set: { preferences.appearance = $0 })
    }

    /// Read by `BodyMapView` to pick the male or female anatomical figure (MuscleMap ships no
    /// androgynous figure, so "Neutral" falls back to the male one — see
    /// `BodyMapView.gender(for:)`); the set of `Muscle` regions it draws never changes.
    private var bodyFigureBinding: Binding<Preferences.BodyFigure> {
        Binding(get: { preferences.bodyFigure }, set: { preferences.bodyFigure = $0 })
    }

    private var keepScreenAwakeBinding: Binding<Bool> {
        Binding(get: { preferences.keepScreenAwake }, set: { preferences.keepScreenAwake = $0 })
    }

    /// Forces the recovery map and consistency calendar onto the blue→yellow accessible ramp
    /// (`DGColor.recoveryAccessible`/`consistencyAccessible`) even when the system-wide
    /// "Differentiate Without Color" setting is off — see `Preferences.colorBlindHeatmaps`.
    private var colorBlindHeatmapsBinding: Binding<Bool> {
        Binding(
            get: { preferences.colorBlindHeatmaps }, set: { preferences.colorBlindHeatmaps = $0 }
        )
    }

    private var lockPhotosBinding: Binding<Bool> {
        Binding(get: { preferences.lockPhotos }, set: { preferences.lockPhotos = $0 })
    }
}

/// One tappable accent-colour circle in the "Accent" row; the selection wears a dark ring.
private struct AccentSwatch: View {
    let accent: DGAccent
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onSelect) {
            Circle()
                .fill(accent.base(dark: scheme == .dark))
                .frame(width: 26, height: 26)
                .padding(2.5)
                .overlay {
                    Circle().strokeBorder(
                        isSelected ? DGColor.ink1.opacity(0.35) : .clear, lineWidth: 2.5
                    )
                }
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(accent.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    NavigationStack {
        SettingsPage(title: "Display") { DisplaySettingsSection() }
    }
    .environment(Preferences())
}
