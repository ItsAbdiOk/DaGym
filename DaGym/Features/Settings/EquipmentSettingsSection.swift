import GymCore
import SwiftUI

/// Settings › Equipment profiles (also the You hub's "Equipment profiles" row, via
/// `EquipmentProfilesScreen`): pick which profile is active, add one, and open
/// `EquipmentProfileView` to edit. A second group summarises the active profile — bar,
/// collars, plates, equipment, machines — each row opening the same editor.
struct EquipmentSettingsSection: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var profiles: [EquipmentProfileInfo] = []
    @State private var editingProfile: EquipmentProfileInfo?
    @State private var isNewProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            profilesGroup
            if let active = profiles.first(where: \.isActive) {
                activeSummary(active)
            }
        }
        .task { refresh() }
        .onChange(of: store.changeToken) { refresh() }
        .sheet(item: $editingProfile, onDismiss: refresh) { profile in
            EquipmentProfileView(
                profile: profile, isNew: isNewProfile,
                onDelete: isNewProfile ? nil : { store.deleteProfile(id: profile.id); refresh() }
            )
            .environment(store)
            .environment(preferences)
        }
    }

    private var profilesGroup: some View {
        SettingsSection(
            title: "Profiles",
            note: "The library shows the active profile’s equipment; routines that need more get a badge."
        ) {
            ForEach(profiles) { profile in
                profileRow(profile)
                SettingsDivider()
            }
            SettingsLinkRow(label: "Add profile", action: addProfile)
        }
    }

    private func addProfile() {
        isNewProfile = true
        editingProfile = EquipmentProfileInfo(
            id: UUID(), name: "New Profile", isActive: false,
            barKg: preferences.weightUnit.defaultBar.weightKg,
            availableEquipment: [], plateStock: [], collarsKg: 0
        )
    }

    private func edit(_ profile: EquipmentProfileInfo) {
        isNewProfile = false
        editingProfile = profile
    }

    private func profileRow(_ profile: EquipmentProfileInfo) -> some View {
        HStack(spacing: DGSpace.s3) {
            Button { store.setActive(id: profile.id); refresh() } label: {
                Image(systemName: profile.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(profile.isActive ? DGColor.coral : DGColor.ink4)
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel(
                profile.isActive ? "\(profile.name), active profile" : "Make \(profile.name) active"
            )
            .accessibilityAddTraits(profile.isActive ? .isSelected : [])
            Text(profile.name).font(DGFont.subhead).foregroundStyle(DGColor.ink1)
            Spacer()
            Button { edit(profile) } label: {
                HStack(spacing: DGSpace.s2) {
                    if profile.isActive {
                        Text("Active").font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                    }
                    SettingsChevron()
                }
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Edit \(profile.name)")
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 46)
    }

    /// The active profile at a glance; every row opens the editor, since the values are edited
    /// there and not inline.
    private func activeSummary(_ profile: EquipmentProfileInfo) -> some View {
        SettingsSection(
            title: profile.name,
            note: "Profiles drive plate maths, swap suggestions, library filtering and what the coach "
                + "may propose."
        ) {
            SettingsLinkRow(label: "Bar weight", value: weight(profile.barKg)) { edit(profile) }
            SettingsDivider()
            SettingsLinkRow(label: "Collars", value: weight(profile.collarsKg)) { edit(profile) }
            SettingsDivider()
            SettingsLinkRow(label: "Plate inventory", value: Self.plateLabel(profile.plateStock)) {
                edit(profile)
            }
            SettingsDivider()
            SettingsLinkRow(
                label: "Available equipment", value: "\(profile.availableEquipment.count) types"
            ) {
                edit(profile)
            }
            SettingsDivider()
            SettingsLinkRow(label: "Machines", value: Self.machinesLabel(profile)) { edit(profile) }
        }
    }

    private func weight(_ kg: Double) -> String {
        "\(preferences.formatWeight(kg: kg)) \(preferences.unitSymbol)"
    }

    /// "8 sizes" — one row of stock per plate weight, however many of each.
    private static func plateLabel(_ stock: [PlateStock]) -> String {
        let sizes = stock.filter { $0.count >= 1 }.count
        return sizes == 1 ? "1 size" : "\(sizes) sizes"
    }

    private static func machinesLabel(_ profile: EquipmentProfileInfo) -> String {
        guard profile.restrictsMachines else { return "Any" }
        let count = profile.availableMachines.count
        return count == 1 ? "1 station" : "\(count) stations"
    }

    private func refresh() {
        profiles = store.equipmentProfiles()
    }
}

#Preview {
    if let store = PreviewStore.make() {
        EquipmentSeeder.seedIfNeeded(store: store)
        return AnyView(
            NavigationStack {
                SettingsPage(title: "Equipment profiles") { EquipmentSettingsSection() }
            }
            .environment(store)
            .environment(Preferences())
        )
    }
    return AnyView(EmptyView())
}
