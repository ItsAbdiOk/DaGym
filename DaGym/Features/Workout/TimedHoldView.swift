import GymCore
import SwiftUI

/// Live timer card for a timed-hold set: 3-2-1 lead-in, then counts up (or
/// down to the target and keeps counting), pause/resume, and a stop button
/// that logs the duration. See mockup 10_01 "Timed hold · live work timer".
struct TimedHoldCard: View {
    var exerciseName: String
    var hold: WorkoutSession.TimedHoldState
    var onPauseResume: () -> Void
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: DGSpace.s4) {
            Text("Timed hold · live work timer").dgLabel(DGColor.success)
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
                .animation(DGMotion.timer, value: hold.elapsed)
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
        }
        .frame(width: 148, height: 148)
    }

    private var controls: some View {
        HStack(spacing: DGSpace.s3) {
            Button(action: onPauseResume) {
                Text(hold.isPaused ? "Resume" : "Pause")
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .dgGlass(.regular, in: Capsule())
            }
            .buttonStyle(DGPressStyle())
            Button(action: onStop) {
                Text("Stop")
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DGColor.coral, in: Capsule())
            }
            .buttonStyle(DGPressStyle())
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

#Preview {
    TimedHoldCard(
        exerciseName: "Plank",
        hold: WorkoutSession.TimedHoldState(
            exerciseID: UUID(), setID: UUID(), targetSeconds: 60, leadIn: 0, elapsed: 47, isPaused: false
        ),
        onPauseResume: {}, onStop: {}
    )
    .padding()
    .background(AmbientWash())
}
