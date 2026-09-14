import GymCore
import SwiftUI

/// A keypad-style ± bodyweight stepper in the user's unit, used for two things: logging a
/// reading (saves a `BodyMeasurementModel` and, when bodyweight sync is on, pushes it to Apple
/// Health — plan.md §6.8) and setting the goal weight `BodyView`'s chart draws its goal line
/// against (`Preferences.bodyweightGoalKg`). Reached from the Body tab and Settings.
struct BodyweightSheet: View {
    enum Purpose {
        case log, goal
    }

    var purpose: Purpose = .log

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(HealthSyncService.self) private var healthSync
    @Environment(\.dismiss) private var dismiss

    @State private var kg: Double = 75

    var body: some View {
        VStack(spacing: DGSpace.s6) {
            Text(purpose == .goal ? "Goal Bodyweight" : "Bodyweight").dgLabel()
            stepperRow
            Text(preferences.unitSymbol.uppercased()).dgLabel()
            quickSteps
            DGPrimaryButton(title: "Save", symbol: "checkmark", fill: DGColor.success, height: 52) {
                save()
            }
            if purpose == .goal, preferences.bodyweightGoalKg != nil {
                Button("Clear goal", action: clearGoal)
                    .buttonStyle(.dgControl)
                    .dgLabel(DGColor.danger)
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, DGSpace.s8)
        .padding(.bottom, DGSpace.s4)
        .presentationDetents([.height(purpose == .goal ? 400 : 360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
        .task { kg = initialKg }
    }

    /// The current goal when editing it; otherwise the latest reading (a sensible goal start too).
    private var initialKg: Double {
        if purpose == .goal, let goal = preferences.bodyweightGoalKg { return goal }
        return store.latestBodyMeasurement()?.bodyweightKg ?? kg
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
        .buttonStyle(.dgControl)
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
        switch purpose {
        case .goal:
            preferences.bodyweightGoalKg = kg
        case .log:
            store.logBodyweight(kg: kg, source: "manual")
            if preferences.healthSyncBodyweight {
                Task { await healthSync.pushBodyweight(kg: kg) }
            }
        }
        dismiss()
    }

    private func clearGoal() {
        preferences.bodyweightGoalKg = nil
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
