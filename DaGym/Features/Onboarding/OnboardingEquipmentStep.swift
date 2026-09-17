import SwiftUI

/// Step 4, "Where do you train?" — picks the active `EquipmentProfileInfo` ("Gym" or "Home",
/// seeded by `EquipmentSeeder`) via `store.setActive(id:)`, immediately.
struct OnboardingEquipmentStep: View {
    var onNext: () -> Void
    @Environment(WorkoutStore.self) private var store
    @State private var profiles: [EquipmentProfileInfo] = []

    var body: some View {
        OnboardingPage(
            step: .equipment, name: "equipment", symbol: "shippingbox.fill", title: "Where do you train?",
            message: "Equipment drives plate maths, swaps and what the coach suggests.",
            cta: "Continue", onContinue: onNext
        ) {
            OnboardingOptionGroup {
                ForEach(profiles) { profile in
                    OnboardingOptionRow(
                        title: profile.name, sub: Self.sub(for: profile), isSelected: profile.isActive
                    ) {
                        store.setActive(id: profile.id)
                        refresh()
                        Haptics.step()
                    }
                }
            }
        }
        .task { refresh() }
    }

    /// "Barbell, cable, machine +4" — what the profile actually holds, never a canned line.
    private static func sub(for profile: EquipmentProfileInfo) -> String? {
        let names = profile.availableEquipment.sorted()
        guard !names.isEmpty else { return "No equipment listed" }
        let shown = names.prefix(3).map(\.capitalized).joined(separator: ", ")
        let rest = names.count - min(3, names.count)
        return rest > 0 ? "\(shown) +\(rest)" : shown
    }

    private func refresh() { profiles = store.equipmentProfiles() }
}

#Preview {
    if let store = PreviewStore.make() {
        return AnyView(
            ZStack {
                DGColor.bgBase.ignoresSafeArea()
                OnboardingEquipmentStep(onNext: {})
                    .environment(store)
            }
        )
    }
    return AnyView(EmptyView())
}
