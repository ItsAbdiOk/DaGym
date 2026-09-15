import GymCore
import SwiftUI

/// 2F timed hold: the reps card becomes a count-up ring ("0:32 holding") with the 3-2-1 lead-in
/// before it. Cardio (not in the spec) takes the same ring with a distance stepper beneath it.
/// The ring is 9 pt live and 6 pt in always-on (see `AlwaysOnActiveView`).
struct TimedSetView: View {
    @Environment(WatchStore.self) private var store
    var entry: WorkoutExerciseEntry
    var set: SetEntry
    var shape: SetShape
    @Binding var focus: CrownField?
    var unit: WeightUnit
    var onFocus: (CrownField) -> Void
    var onAdjust: (CrownField, AccessibilityAdjustmentDirection) -> Void

    private var hold: WorkoutSession.TimedHoldState? {
        guard let hold = store.session?.timedHold, hold.setID == set.id else { return nil }
        return hold
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RingView(progress: progress, lineWidth: shape == .cardio ? 6 : 9)
                VStack(spacing: 0) {
                    Text(clock)
                        .font(WatchFont.value(shape == .cardio ? (WatchMetric.isSmall ? 14 : 17) : 30))
                        .foregroundStyle(WatchColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(caption)
                        .font(WatchFont.unit)
                        .foregroundStyle(WatchColor.inkSecondary)
                }
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(caption), \(clock)")
            if shape == .cardio {
                StepperCard(
                    value: distanceUnit.format(meters: set.cardioMeters ?? 0), label: distanceUnit.symbol,
                    field: .distance, focus: focus, height: WatchMetric.isSmall ? 36 : 40,
                    accessibilityName: "Distance",
                    accessibilityValue: distanceUnit.formatWithSymbol(meters: set.cardioMeters ?? 0),
                    onTap: { onFocus(.distance) }, onAdjust: { onAdjust(.distance, $0) }
                )
            }
        }
    }

    private var ringSize: CGFloat {
        if shape == .cardio { return WatchMetric.isSmall ? 48 : 58 }
        return WatchMetric.isSmall ? 84 : 96
    }
    private var distanceUnit: DistanceUnit { DistanceUnit.matching(unit) }

    private var progress: Double {
        guard let hold, hold.leadIn == 0 else { return 0 }
        guard let target = hold.targetSeconds, target > 0 else { return 0 }
        return Double(hold.elapsed) / Double(target)
    }

    private var clock: String {
        guard let hold else { return WorkoutSession.clock(set.cardioSeconds ?? 0) }
        return hold.leadIn > 0 ? "\(hold.leadIn)" : WorkoutSession.clock(hold.elapsed)
    }

    private var caption: String {
        guard let hold else { return "target" }
        if hold.leadIn > 0 { return "get ready" }
        return shape == .cardio ? "running" : "holding"
    }
}
