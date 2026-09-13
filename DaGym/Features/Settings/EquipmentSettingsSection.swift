import GymCore
import SwiftUI

/// The Settings "EQUIPMENT" section: pick which profile is active, and open
/// `EquipmentProfileView` to edit or add one. Library filtering by profile
/// and routine equipment warnings (plan.md §6.1) are a follow-up — this only
/// stores and edits the profiles.
struct EquipmentSettingsSection: View {
    @Environment(WorkoutStore.self) private var store

    @State private var profiles: [EquipmentProfileInfo] = []
    @State private var editingProfile: EquipmentProfileInfo?
    @State private var isNewProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            header
            VStack(spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    profileRow(profile)
                    if index < profiles.count - 1 {
                        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                    }
                }
            }
            .dgCard(padding: 0)
            Text("The library shows the active profile’s equipment; routines that need more get a badge.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
        .task { refresh() }
        .onChange(of: store.changeToken) { refresh() }
        .sheet(item: $editingProfile, onDismiss: refresh) { profile in
            EquipmentProfileView(
                profile: profile, isNew: isNewProfile,
                onDelete: isNewProfile ? nil : { store.deleteProfile(id: profile.id); refresh() }
            )
            .environment(store)
        }
    }

    private var header: some View {
        HStack {
            Text("Equipment").dgLabel()
            Spacer()
            Button {
                isNewProfile = true
                editingProfile = EquipmentProfileInfo(
                    id: UUID(), name: "New Profile", isActive: false, barKg: 20,
                    availableEquipment: [], plateStock: [], collarsKg: 0
                )
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DGColor.coral)
            }
            .buttonStyle(.plain)
        }
    }

    private func profileRow(_ profile: EquipmentProfileInfo) -> some View {
        HStack(spacing: DGSpace.s3) {
            Button { store.setActive(id: profile.id); refresh() } label: {
                Image(systemName: profile.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(profile.isActive ? DGColor.coral : DGColor.ink4)
            }
            .buttonStyle(.plain)
            Text(profile.name).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Button {
                isNewProfile = false
                editingProfile = profile
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private func refresh() {
        profiles = store.equipmentProfiles()
    }
}

#Preview {
    if let store = PreviewStore.make() {
        EquipmentSeeder.seedIfNeeded(store: store)
        return AnyView(
            ScrollView {
                EquipmentSettingsSection()
                    .padding(DGSpace.s4)
            }
            .environment(store)
            .background(AmbientWash())
        )
    }
    return AnyView(EmptyView())
}
