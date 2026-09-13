import SwiftUI

/// The Settings "Display" section: screen-awake and photo-lock toggles, plus the accent-theme
/// picker (plan.md Phase 8). Split out of `SettingsView` to keep that struct's body under
/// SwiftLint's `type_body_length` limit — same pattern as `ICloudSettingsSection` etc.
struct DisplaySettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Display").dgLabel()
            VStack(spacing: 0) {
                row(label: "Keep screen awake", isOn: keepScreenAwakeBinding)
                SettingsSectionDivider()
                row(label: "Lock progress photos", isOn: lockPhotosBinding)
                SettingsSectionDivider()
                accentRow
                SettingsSectionDivider()
                appearanceRow
                SettingsSectionDivider()
                bodyFigureRow
            }
            .dgCard(padding: 0)
        }
    }

    private func row(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Toggle("", isOn: isOn).tint(DGColor.coral).labelsHidden()
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    /// Five accent swatches. Tapping one sets `Preferences.accent`, which updates
    /// `DGColor.current` synchronously — this row (and every other coral-tinted control still on
    /// screen) re-renders the moment `preferences.accent` changes, since it reads that property
    /// directly below.
    private var accentRow: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Accent").font(DGFont.body).foregroundStyle(DGColor.ink1)
            HStack(spacing: DGSpace.s4) {
                ForEach(DGAccent.allCases, id: \.self) { accent in
                    AccentSwatch(accent: accent, isSelected: preferences.accent == accent) {
                        preferences.accent = accent
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.vertical, DGSpace.s3)
    }

    /// System/Light/Dark, applied by whatever reads `preferences.appearance.colorScheme` further
    /// up the view hierarchy (`preferredColorScheme`) — this row only writes the preference.
    private var appearanceRow: some View {
        HStack {
            Text("Appearance").font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Picker("Appearance", selection: appearanceBinding) {
                Text("System").tag(Preferences.Appearance.system)
                Text("Light").tag(Preferences.Appearance.light)
                Text("Dark").tag(Preferences.Appearance.dark)
            }
            .pickerStyle(.segmented)
            .tint(DGColor.coral)
            .frame(width: 200)
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    /// Read by `BodyMapView` for a subtly different shoulder/hip silhouette; the muscle regions
    /// it draws never change.
    private var bodyFigureRow: some View {
        HStack {
            Text("Body figure").font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Picker("Body figure", selection: bodyFigureBinding) {
                Text("Neutral").tag(Preferences.BodyFigure.neutral)
                Text("Male").tag(Preferences.BodyFigure.male)
                Text("Female").tag(Preferences.BodyFigure.female)
            }
            .pickerStyle(.segmented)
            .tint(DGColor.coral)
            .frame(width: 200)
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private var appearanceBinding: Binding<Preferences.Appearance> {
        Binding(get: { preferences.appearance }, set: { preferences.appearance = $0 })
    }

    private var bodyFigureBinding: Binding<Preferences.BodyFigure> {
        Binding(get: { preferences.bodyFigure }, set: { preferences.bodyFigure = $0 })
    }

    private var keepScreenAwakeBinding: Binding<Bool> {
        Binding(get: { preferences.keepScreenAwake }, set: { preferences.keepScreenAwake = $0 })
    }

    private var lockPhotosBinding: Binding<Bool> {
        Binding(get: { preferences.lockPhotos }, set: { preferences.lockPhotos = $0 })
    }
}

/// One tappable accent-colour circle in the "Accent" row; a checkmark marks the selection.
private struct AccentSwatch: View {
    let accent: DGAccent
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onSelect) {
            Circle()
                .fill(accent.base(dark: scheme == .dark))
                .frame(width: 32, height: 32)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle().strokeBorder(DGColor.hairline, lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Hairline separator matching `SettingsView`'s private `SettingsDivider` — duplicated (not
/// shared) since that type is file-private to `SettingsView.swift`.
private struct SettingsSectionDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

#Preview {
    ScrollView {
        DisplaySettingsSection()
            .padding(DGSpace.s4)
    }
    .environment(Preferences())
    .background(AmbientWash())
}
