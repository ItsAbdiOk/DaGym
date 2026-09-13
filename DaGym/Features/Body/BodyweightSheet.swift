import GymCore
import SwiftUI

/// Log a bodyweight reading: a keypad-style ± stepper in the user's unit. Saves a
/// `BodyMeasurementModel` and, when bodyweight sync is on, pushes the same reading to Apple
/// Health (plan.md §6.8). Reached via the "Bodyweight" row in Settings — the dedicated Body tab
/// is Phase 3.
struct BodyweightSheet: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(HealthSyncService.self) private var healthSync
    @Environment(\.dismiss) private var dismiss

    @State private var kg: Double = 75

    var body: some View {
        VStack(spacing: DGSpace.s6) {
            Text("Bodyweight").dgLabel()
            stepperRow
            Text(preferences.unitSymbol.uppercased()).dgLabel()
            quickSteps
            DGPrimaryButton(title: "Save", symbol: "checkmark", fill: DGColor.success, height: 52) {
                save()
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, DGSpace.s8)
        .padding(.bottom, DGSpace.s4)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
        .task { kg = store.latestBodyMeasurement()?.bodyweightKg ?? kg }
    }

    private var stepperRow: some View {
        HStack {
            circleButton(symbol: "minus", fill: DGColor.surface3, ink: DGColor.ink1) {
                step(by: -fineStepKg)
            }
            Spacer(minLength: DGSpace.s4)
            Text(preferences.formatWeight(kg: kg))
                .dgMetric(DGFont.metricXL)
                .foregroundStyle(DGColor.ink1)
            Spacer(minLength: DGSpace.s4)
            circleButton(symbol: "plus", fill: DGColor.coral, ink: DGColor.inkOnCoral) {
                step(by: fineStepKg)
            }
        }
    }

    private var quickSteps: some View {
        HStack(spacing: DGSpace.s2) {
            DGChip(title: "-\(Self.quickAmount)") { step(by: -quickStepKg) }
            DGChip(title: "+\(Self.quickAmount)") { step(by: quickStepKg) }
        }
    }

    private func circleButton(
        symbol: String, fill: Color, ink: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .background(fill, in: Circle())
        }
        .buttonStyle(DGPressStyle())
    }

    private static let quickAmount = 1

    private var fineStepKg: Double { preferences.weightUnit.toKg(preferences.weightUnit.displayStep) }
    private var quickStepKg: Double { preferences.weightUnit.toKg(Double(Self.quickAmount)) }

    private func step(by delta: Double) {
        kg = max(0, kg + delta)
        Haptics.step()
    }

    private func save() {
        Haptics.confirm()
        store.logBodyweight(kg: kg, source: "manual")
        if preferences.healthSyncBodyweight {
            Task { await healthSync.pushBodyweight(kg: kg) }
        }
        dismiss()
    }
}

#Preview {
    if let store = PreviewStore.make() {
        let preferences = Preferences()
        return AnyView(
            Color.clear
                .sheet(isPresented: .constant(true)) { BodyweightSheet() }
                .environment(preferences)
                .environment(store)
                .environment(HealthSyncService(
                    healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                ))
        )
    }
    return AnyView(EmptyView())
}
