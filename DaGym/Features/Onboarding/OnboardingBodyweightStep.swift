import SwiftUI

/// Step 5, "What do you weigh?" — optional, unit-aware bodyweight entry, mirroring
/// `BodyweightSheet`'s stepper. Continue writes a `BodyMeasurementModel`; the top-bar Skip
/// leaves none.
struct OnboardingBodyweightStep: View {
    var onNext: () -> Void
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var kg: Double = 75
    @State private var showKeypad = false

    var body: some View {
        OnboardingPage(
            step: .bodyweight, name: "bodyweight", symbol: "figure.stand", title: "What do you weigh?",
            message: "Optional — powers your bodyweight chart. Log it any time from Settings instead.",
            cta: "Continue", ctaDisabled: !isValid, onContinue: save
        ) {
            OnboardingOptionGroup {
                stepperRow
            }
        }
        .task { kg = store.latestBodyMeasurement()?.bodyweightKg ?? kg }
        .sheet(isPresented: $showKeypad) {
            // Same fine step as the +/- buttons outside (0.25 kg / 0.5 lb), and the bodyweight
            // purpose so the sheet drops the barbell plate line and the "Log set" wording.
            WeightKeypadSheet(
                title: "Weight", value: $kg, step: fineStepKg, bar: nil, last: nil,
                unit: preferences.weightUnit, purpose: .bodyweight, onDone: {}
            )
        }
    }

    private var stepperRow: some View {
        HStack(spacing: DGSpace.s3) {
            stepperButton(symbol: "minus") { step(by: -fineStepKg) }
            Spacer()
            Button {
                Haptics.step()
                showKeypad = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DGSpace.s1) {
                    Text(preferences.formatWeight(kg: kg))
                        .dgMetric(DGFont.metricM)
                        .foregroundStyle(DGColor.ink1)
                    Text(preferences.unitSymbol)
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Weight, \(preferences.formatWeight(kg: kg)) \(preferences.unitSymbol)")
            .accessibilityHint("Opens a keypad to type your weight directly")
            Spacer()
            stepperButton(symbol: "plus", coral: true) { step(by: fineStepKg) }
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: 64)
    }

    private func stepperButton(
        symbol: String, coral: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(coral ? DGColor.inkOnCoral : DGColor.ink1)
                .frame(width: 36, height: 36)
                .background(coral ? DGColor.coral : DGColor.surface3, in: Circle())
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(symbol == "minus" ? "Decrease weight" : "Increase weight")
    }

    private var fineStepKg: Double { preferences.weightUnit.toKg(preferences.weightUnit.displayStep) }

    private func step(by delta: Double) {
        kg = max(0, kg + delta)
        Haptics.step()
    }

    /// A plausible human bodyweight. The keypad can be backspaced to empty, which leaves `kg`
    /// at 0 — logging that would put a 0 kg point on the bodyweight chart and write it to
    /// Health, so Continue stays disabled until the value is real. Skip is always available.
    private var isValid: Bool { kg >= Self.minimumKg && kg <= Self.maximumKg }

    private static let minimumKg: Double = 20
    private static let maximumKg: Double = 500

    private func save() {
        guard isValid else { return }
        store.logBodyweight(kg: kg)
        onNext()
    }
}

#Preview {
    if let store = PreviewStore.make() {
        return AnyView(
            ZStack {
                DGColor.bgBase.ignoresSafeArea()
                OnboardingBodyweightStep(onNext: {})
                    .environment(store)
                    .environment(Preferences())
            }
        )
    }
    return AnyView(EmptyView())
}
