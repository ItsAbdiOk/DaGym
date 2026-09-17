import GymCore
import SwiftUI

/// Settings › Units: the weight unit and, beside it, the distance unit cardio is shown in.
/// Storage stays kg and metres either way (plan.md §3).
struct UnitsSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        SettingsSection(note: "Applies everywhere: logging, plate maths, charts and exports.") {
            SettingsRow(label: "Weight") {
                SettingsSegment(
                    label: "Weight unit", selection: $preferences.weightUnit,
                    options: [(WeightUnit.kg, "kg"), (WeightUnit.lb, "lb")]
                )
            }
            SettingsDivider()
            SettingsRow(label: "Distance") {
                SettingsSegment(
                    label: "Distance unit", selection: $preferences.distanceUnit,
                    options: [(DistanceUnit.km, "km"), (DistanceUnit.mi, "mi")]
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsPage(title: "Units") { UnitsSettingsSection() }
    }
    .environment(Preferences())
}
