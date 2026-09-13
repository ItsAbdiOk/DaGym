import SwiftUI

/// Full-screen rest timer shown between working sets.
struct RestTimerView: View {
    var session: WorkoutSession
    var exerciseName: String
    var onClose: () -> Void

    var body: some View {
        ZStack {
            AmbientWash(heat: 0.9)
            RestGlow()
            VStack(spacing: 0) {
                topBar
                Spacer()
                RestRing(remaining: session.restRemaining, total: session.restTotal)
                Spacer()
                UpNextCard(
                    setLabel: "Up Next · Set \(session.setsDone + 1) Of \(session.setsTotal)",
                    detail: Self.stripNextPrefix(session.restNextLabel)
                )
                .padding(.horizontal, DGSpace.s4)
                controls
                Text("Haptic at 3-2-1 · screen flash and sound optional")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s6)
            }
        }
        .task { await runTicker() }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Text(exerciseName.uppercased()).dgLabel()
            Spacer()
        }
        .padding(.horizontal, DGSpace.s3)
        .padding(.top, DGSpace.s2)
    }

    private var controls: some View {
        VStack(spacing: DGSpace.s3) {
            HStack(spacing: DGSpace.s3) {
                RestAdjustButton(title: "−30s") { session.adjustRest(by: -30) }
                RestAdjustButton(title: "+30s") { session.adjustRest(by: 30) }
            }
            DGPrimaryButton(title: "Skip Rest", symbol: "forward.fill", action: session.skipRest)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.top, DGSpace.s5)
    }

    private func runTicker() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            session.tickRest()
        }
    }

    private static func stripNextPrefix(_ label: String) -> String {
        label.hasPrefix("Next ") ? String(label.dropFirst(5)) : label
    }
}

/// Coral radial glow behind the ring.
private struct RestGlow: View {
    var body: some View {
        RadialGradient(
            colors: [DGColor.coral.opacity(0.28), .clear],
            center: .center, startRadius: 10, endRadius: 220
        )
        .frame(width: 440, height: 440)
        .allowsHitTesting(false)
    }
}

/// 240pt depleting ring with the mm:ss remaining at its centre.
private struct RestRing: View {
    var remaining: Int
    var total: Int

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(remaining) / CGFloat(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DGColor.ink4.opacity(0.3), lineWidth: 12)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(DGColor.coral, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(DGMotion.timer, value: remaining)
            VStack(spacing: DGSpace.s1) {
                Text(WorkoutSession.clock(remaining))
                    .font(Font.custom(DGFont.Family.condensedExtraBold, size: 64))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(DGColor.ink1)
                    .contentTransition(.identity)
                Text("Of \(WorkoutSession.clock(total)) rest".uppercased()).dgLabel()
            }
        }
        .frame(width: 240, height: 240)
    }
}

/// "Up next" summary card sitting under the ring.
private struct UpNextCard: View {
    var setLabel: String
    var detail: String

    var body: some View {
        VStack(spacing: DGSpace.s1) {
            Text(setLabel).dgLabel()
            Text(detail)
                .dgMetric(DGFont.metricM, tracking: -0.5)
                .foregroundStyle(DGColor.ink1)
        }
        .frame(maxWidth: .infinity)
        .dgCard(padding: DGSpace.s4)
    }
}

/// −30s / +30s glass adjustment button.
private struct RestAdjustButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DGFont.condensedLabel(17))
                .foregroundStyle(DGColor.ink1)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .dgGlass(.regular, radius: DGRadius.md)
        }
        .buttonStyle(DGPressStyle())
    }
}

#Preview {
    RestTimerView(session: SampleData.makeSession(), exerciseName: "Bench Press", onClose: {})
}
