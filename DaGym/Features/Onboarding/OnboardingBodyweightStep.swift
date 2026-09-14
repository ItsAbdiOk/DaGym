import SwiftUI

/// "What do you weigh?" — optional, unit-aware bodyweight entry, mirroring
/// `BodyweightSheet`'s stepper. Saving writes a `BodyMeasurementModel`;
/// skipping leaves none.
struct OnboardingBodyweightStep: View {
    var onNext: () -> Void
    var onSkip: () -> Void
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var kg: Double = 75
    @State private var showKeypad = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            Text("What do\nyou weigh?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("Optional — powers your bodyweight chart. Log it any time from Settings instead.")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
            stepperRow
            Spacer()
            VStack(spacing: DGSpace.s3) {
                DGPrimaryButton(title: "Save & Continue", action: save)
                    .accessibilityIdentifier(A11yID.onboardingNext)
                Button("Skip", action: onSkip)
                    .buttonStyle(.dgControl)
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink3)
                    .accessibilityIdentifier(A11yID.onboardingSkip)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { kg = store.latestBodyMeasurement()?.bodyweightKg ?? kg }
        .sheet(isPresented: $showKeypad) {
            WeightKeypadSheet(
                title: "Weight", value: $kg, step: preferences.weightUnit.defaultIncrementKg,
                bar: nil, last: nil, unit: preferences.weightUnit, onDone: {}
            )
        }
    }

    private var stepperRow: some View {
        HStack {
            stepperButton(symbol: "minus") { step(by: -fineStepKg) }
            Spacer()
            Button {
                Haptics.step()
                showKeypad = true
            } label: {
                VStack(spacing: 0) {
                    Text(preferences.formatWeight(kg: kg))
                        .dgMetric(DGFont.metricXL)
                        .foregroundStyle(DGColor.ink1)
                    Text(preferences.unitSymbol.uppercased()).dgLabel()
                }
                .overlay(alignment: .top) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DGColor.ink4)
                        .offset(x: 44, y: -4)
                }
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Weight, \(preferences.formatWeight(kg: kg)) \(preferences.unitSymbol)")
            .accessibilityHint("Opens a keypad to type your weight directly")
            Spacer()
            stepperButton(symbol: "plus", coral: true) { step(by: fineStepKg) }
        }
        .dgCard()
    }

    private func stepperButton(
        symbol: String, coral: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(coral ? DGColor.inkOnCoral : DGColor.ink1)
                .frame(width: 44, height: 44)
                .background(coral ? DGColor.coral : DGColor.surface3, in: Circle())
        }
        .buttonStyle(.dgControl)
    }

    private var fineStepKg: Double { preferences.weightUnit.toKg(preferences.weightUnit.displayStep) }

    private func step(by delta: Double) {
        kg = max(0, kg + delta)
        Haptics.step()
    }

    private func save() {
        store.logBodyweight(kg: kg)
        onNext()
    }
}

#Preview {
    if let store = PreviewStore.make() {
        return AnyView(
            ZStack {
                AmbientWash()
                OnboardingBodyweightStep(onNext: {}, onSkip: {})
                    .environment(store)
                    .environment(Preferences())
                    .padding(DGSpace.s5)
            }
        )
    }
    return AnyView(EmptyView())
}
