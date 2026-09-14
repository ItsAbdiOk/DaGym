import GymCore
import SwiftUI

/// Settings › Units: the weight unit and, beside it, the distance unit cardio is shown in.
/// Storage stays kg and metres either way (plan.md §3).
struct UnitsSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        SettingsSection(title: "Units") {
            SettingsRow(label: "Weight unit") {
                Picker("Weight unit", selection: $preferences.weightUnit) {
                    Text("KG").tag(WeightUnit.kg)
                    Text("LB").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                .tint(DGColor.coral)
                .frame(width: 120)
            }
            SettingsRow(label: "Distance unit") {
                Picker("Distance unit", selection: $preferences.distanceUnit) {
                    Text("KM").tag(DistanceUnit.km)
                    Text("MI").tag(DistanceUnit.mi)
                }
                .pickerStyle(.segmented)
                .tint(DGColor.coral)
                .frame(width: 120)
            }
        }
    }
}
