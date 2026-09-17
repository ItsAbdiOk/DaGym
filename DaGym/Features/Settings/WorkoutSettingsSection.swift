import GymCore
import SwiftUI

/// Settings › Workout: the saved active-workout layout (Cards / List / Compact) and the set-row
/// ± steppers. The active screen's "…" menu can override the layout for one session; this is
/// where the default changes.
struct WorkoutSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        SettingsSection(note: preferences.workoutLayout.settingsDetail) {
            SettingsRow(label: "Layout") {
                SettingsSegment(
                    label: "Layout", selection: binding(\.workoutLayout),
                    options: WorkoutLayout.allCases.map { ($0, $0.title) }
                )
                .accessibilityIdentifier(A11yID.settingsWorkoutLayout)
            }
            SettingsDivider()
            SettingsToggleRow(label: "Set steppers", isOn: binding(\.showSetSteppers))
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
    NavigationStack {
        SettingsPage(title: "Workout") { WorkoutSettingsSection() }
    }
    .environment(Preferences())
}
