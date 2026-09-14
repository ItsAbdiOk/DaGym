import SwiftUI

/// "Where do you train?" — mockup 06_01 "15c". Picks the active
/// `EquipmentProfileInfo` ("Gym" or "Home", seeded by `EquipmentSeeder`)
/// via `store.setActive(id:)`, immediately.
struct OnboardingEquipmentStep: View {
    var onNext: () -> Void
    @Environment(WorkoutStore.self) private var store
    @State private var profiles: [EquipmentProfileInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            Text("Where do\nyou train?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("This decides what the plate calculator and swap suggestions assume you have access to.")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
            HStack(spacing: DGSpace.s2) {
                ForEach(profiles) { profile in
                    DGChip(title: profile.name, selected: profile.isActive) {
                        store.setActive(id: profile.id)
                        refresh()
                        Haptics.step()
                    }
                }
            }
            Spacer()
            DGPrimaryButton(title: "Continue", action: onNext)
                .accessibilityIdentifier(A11yID.onboardingNext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { refresh() }
    }

    private func refresh() { profiles = store.equipmentProfiles() }
}

#Preview {
    if let store = PreviewStore.make() {
        return AnyView(
            ZStack {
                AmbientWash()
                OnboardingEquipmentStep(onNext: {})
                    .environment(store)
                    .padding(DGSpace.s5)
            }
        )
    }
    return AnyView(EmptyView())
}
