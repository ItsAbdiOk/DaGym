import GymCore
import SwiftUI

/// "How do you measure things?" — mockup 06_00 "15b" (units half). Sets
/// `preferences.weightUnit` immediately on tap.
struct OnboardingUnitsStep: View {
    var onNext: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            Text("How do you\nmeasure things?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Units").dgLabel()
                HStack(spacing: DGSpace.s2) {
                    unitChip(.kg, title: "Kilograms")
                    unitChip(.lb, title: "Pounds")
                }
            }
            .dgCard()
            Spacer()
            DGPrimaryButton(title: "Continue", action: onNext)
                .accessibilityIdentifier(A11yID.onboardingNext)
        }
    }

    private func unitChip(_ unit: WeightUnit, title: String) -> some View {
        DGChip(title: title, selected: preferences.weightUnit == unit) {
            preferences.weightUnit = unit
            Haptics.step()
        }
    }
}

#Preview {
    ZStack {
        AmbientWash()
        OnboardingUnitsStep(onNext: {})
            .environment(Preferences())
            .padding(DGSpace.s5)
    }
}
