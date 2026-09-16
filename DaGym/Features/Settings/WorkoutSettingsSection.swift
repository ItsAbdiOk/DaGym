import GymCore
import SwiftUI

/// The Settings "WORKOUT" card: the saved active-workout layout (Cards / List / Compact) and
/// the set-row ± steppers. The active screen's "…" menu can override the layout for one
/// session; this is where the default changes.
struct WorkoutSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            rows
            Text(preferences.workoutLayout.settingsDetail)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var rows: some View {
        SettingsSection(title: "Workout") {
            SettingsRow(label: "Layout") {
                Picker("Layout", selection: binding(\.workoutLayout)) {
                    ForEach(WorkoutLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .tint(DGColor.coral)
                .frame(width: 220)
                .accessibilityIdentifier(A11yID.settingsWorkoutLayout)
            }
            SettingsDivider()
            SettingsRow(label: "Set steppers") {
                Toggle("Set steppers", isOn: binding(\.showSetSteppers)).tint(DGColor.coral).labelsHidden()
            }
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }
}

extension WorkoutLayout {
    /// The one-line explanation under the Settings picker.
    var settingsDetail: String {
        switch self {
        case .cards: "Cards: the exercise you're on gets a full card with plates, last sessions and coaching."
        case .list: "List: every set of every exercise in one dense list — handy for supersets."
        case .compact: "Compact: the on-deck card with just its set rows."
        }
    }
}

#Preview {
    ScrollView {
        WorkoutSettingsSection().padding(DGSpace.s4)
    }
    .environment(Preferences())
    .background(AmbientWash())
}
