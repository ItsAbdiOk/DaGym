import GymCore
import SwiftUI

/// Live timer card for a timed-hold set: 3-2-1 lead-in, then counts up (or
/// down to the target and keeps counting), pause/resume, and a stop button
/// that logs the duration. See mockup 10_01 "Timed hold · live work timer".
struct TimedHoldCard: View {
    var exerciseName: String
    var hold: WorkoutSession.TimedHoldState
    /// A cardio set counts up the same way; only the label changes.
    var isCardio = false
    var onPauseResume: () -> Void
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: DGSpace.s4) {
            Text(isCardio ? "Cardio · live work timer" : "Timed hold · live work timer")
                .dgLabel(DGColor.success)
            ring
            controls
        }
        .dgCard(padding: DGSpace.s4)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(DGColor.hairline, lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(DGColor.success, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .dgAnimation(DGMotion.timer, value: hold.elapsed)
            VStack(spacing: 2) {
                Text(exerciseName.uppercased())
                    .font(DGFont.condensedLabel(12))
                    .foregroundStyle(DGColor.ink3)
                Text(displayValue)
                    .dgMetric(DGFont.metricXL)
                    .foregroundStyle(DGColor.ink1)
                if let target = hold.targetSeconds {
                    Text("Target \(WorkoutSession.clock(target))").dgLabel()
                }
            }
            .accessibilityElement(children: .combine)
        }
        .frame(width: 148, height: 148)
        // The ring's number must stay inside the ring; the card's label and buttons still grow.
        .dgDenseType()
    }

    private var controls: some View {
        HStack(spacing: DGSpace.s3) {
            Button(action: onPauseResume) {
                Text(hold.isPaused ? "Resume" : "Pause")
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .dgGlass(.regular, in: Capsule())
            }
            .buttonStyle(.dgControl)
            Button(action: onStop) {
                Text("Stop")
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(DGColor.coral, in: Capsule())
            }
            .buttonStyle(.dgControl)
        }
    }

    /// The lead-in countdown, then the running clock.
    private var displayValue: String {
        if hold.leadIn > 0 { return "\(hold.leadIn)" }
        return WorkoutSession.clock(hold.elapsed)
    }

    private var progress: Double {
        guard hold.leadIn == 0, let target = hold.targetSeconds, target > 0 else { return 0 }
        return min(1, Double(hold.elapsed) / Double(target))
    }
}

/// One hold in the on-deck card: badge · target · logged time · Start (or the done check once
/// logged). The Start button is what opens `TimedHoldCard`; before this row existed a hold could
/// only be started while its exercise was still collapsed.
struct TimedSetRow: View {
    var set: SetEntry
    var badgeIndex: Int
    var isCurrent: Bool
    var onStart: () -> Void
    var onToggleDone: () -> Void

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            SetKindBadge(kind: set.kind, index: badgeIndex)
            Text(set.targetSeconds.map(WorkoutSession.clock) ?? "–")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .frame(minWidth: 44, alignment: .leading)
                .accessibilityLabel("Target")
                .accessibilityValue(set.targetSeconds.map(WorkoutSession.clock) ?? "no target")
            Text(set.durationSeconds.map(WorkoutSession.clock) ?? "–")
                .dgMetric(DGFont.metricM)
                .foregroundStyle(set.isDone ? DGColor.ink1 : DGColor.ink3)
                .frame(minWidth: 44, alignment: .leading)
                .accessibilityLabel("Held")
                .accessibilityValue(set.durationSeconds.map(WorkoutSession.clock) ?? "not logged")
            Spacer(minLength: 0)
            if set.isDone {
                Button(action: onToggleDone) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(DGColor.success)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel(Self.doneLabel(set: set))
                .accessibilityAddTraits(.isSelected)
            } else {
                Button(action: onStart) {
                    Text("Start")
                        .font(DGFont.condensedLabel(12))
                        .textCase(.uppercase)
                        .foregroundStyle(isCurrent ? DGColor.inkOnCoral : DGColor.ink1)
                        .padding(.horizontal, DGSpace.s3)
                        .frame(minHeight: 36)
                        .background(isCurrent ? DGColor.coral : DGColor.surface3, in: Capsule())
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel(isCurrent ? "Start hold, current set" : "Start hold")
            }
        }
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: DGTap.rowHeight)
        .dgDenseType()
        .background(rowFill, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                .strokeBorder(DGColor.coral, lineWidth: isCurrent ? 1 : 0)
        }
    }

    /// "Hold done, 0:45, tap to undo" — the check is otherwise a bare symbol.
    static func doneLabel(set: SetEntry) -> String {
        let held = set.durationSeconds.map(WorkoutSession.clock) ?? "no time"
        return "Hold done, \(held), tap to undo"
    }

    private var rowFill: Color {
        if set.isDone { return DGColor.success.opacity(0.16) }
        return DGColor.surface2
    }
}

#Preview {
    TimedHoldCard(
        exerciseName: "Plank",
        hold: WorkoutSession.TimedHoldState(
            exerciseID: UUID(), setID: UUID(), targetSeconds: 60, startedAt: Date(), leadIn: 0, elapsed: 47
        ),
        onPauseResume: {}, onStop: {}
    )
    .padding()
    .background(AmbientWash())
}
