import GymCore
import SwiftUI

/// Step 1, "Units": metric or imperial. Sets `preferences.weightUnit` and `distanceUnit`
/// together, immediately on tap.
struct OnboardingUnitsStep: View {
    var onNext: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        OnboardingPage(
            step: .units, name: "units", symbol: "scalemass.fill", title: "Units",
            message: "Used for logging, plate maths and every chart.", cta: "Continue", onContinue: onNext
        ) {
            OnboardingOptionGroup {
                OnboardingOptionRow(
                    title: "Kilograms", sub: "kg · km — metric", isSelected: preferences.weightUnit == .kg
                ) { pick(.kg, .km) }
                OnboardingOptionRow(
                    title: "Pounds", sub: "lb · mi — imperial", isSelected: preferences.weightUnit == .lb
                ) { pick(.lb, .mi) }
            }
        }
    }

    private func pick(_ weight: WeightUnit, _ distance: DistanceUnit) {
        preferences.weightUnit = weight
        preferences.distanceUnit = distance
        Haptics.step()
    }
}

#Preview {
    ZStack {
        DGColor.bgBase.ignoresSafeArea()
        OnboardingUnitsStep(onNext: {})
            .environment(Preferences())
    }
}
