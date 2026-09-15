import GymCore
import SwiftUI

/// 3B: rests over 45 s take the whole screen — the ring, the remaining time over the total,
/// the next set, +30s / Skip. The crown scrubs the remaining time in 15 s detents, each detent
/// a step from the current countdown. For the
/// final three seconds (3C) the buttons clear so a stray palm can't skip, and at zero it hands
/// straight back to the next set.
struct FullScreenRestView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences
    @State private var crown: Double = 0
    @State private var scrubber = CrownRestScrubber(position: 0)

    private var session: WorkoutSession? { store.session }
    private var remaining: Int { session?.restRemaining ?? 0 }
    private var isFinalThree: Bool { remaining <= 3 && remaining > 0 }

    var body: some View {
        VStack(spacing: 0) {
            if isFinalThree {
                finalThree
            } else {
                counting
            }
        }
        .padding(.horizontal, WatchMetric.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchColor.background)
        .focusable(!isFinalThree)
        .digitalCrownRotation(
            $crown, from: 0, through: 600, by: Double(CrownDetents.restSeconds), sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            // Parked mid-range so a turn in either direction has room; the position itself
            // means nothing — only movement does (`CrownRestScrubber`).
            crown = 300
            scrubber = CrownRestScrubber(position: crown)
        }
        .onChange(of: crown) { _, value in
            let delta = scrubber.turned(to: value)
            guard delta != 0 else { return }
            store.scrubRest(to: remaining + delta)
        }
    }

    private var counting: some View {
        VStack(spacing: 2) {
            SafeBandText(text: "Rest · \(nextSetLine)")
            ZStack {
                RingView(progress: progress, lineWidth: 9)
                VStack(spacing: 0) {
                    Text(WorkoutSession.clock(remaining))
                        .font(WatchFont.value(34, weight: .bold))
                        .foregroundStyle(WatchColor.ink)
                    Text("of \(WorkoutSession.clock(session?.restTotal ?? 0))")
                        .font(WatchFont.secondary)
                        .foregroundStyle(WatchColor.inkSecondary)
                }
            }
            .frame(width: ringSize, height: ringSize)
            .padding(.vertical, 2)
            // Announced by `WatchStore` at 30 s and zero only; the label itself never ticks.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest timer, of \(WorkoutSession.clock(session?.restTotal ?? 0))")
            if let session {
                Text(RestLine.next(session: session, unit: preferences.weightUnit, withUnit: true))
                    .font(WatchFont.body)
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            RestButtonRow()
            Spacer(minLength: 2)
        }
    }

    private var finalThree: some View {
        VStack(spacing: 4) {
            Spacer()
            Text("\(remaining)")
                .font(WatchFont.value(54, weight: .bold))
                .foregroundStyle(WatchColor.accent)
                .contentTransition(.numericText(countsDown: true))
            Text("Get ready")
                .font(WatchFont.bodyMedium)
                .foregroundStyle(WatchColor.ink)
            if let session {
                Text(RestLine.next(session: session, unit: preferences.weightUnit, withUnit: true)
                    .replacingOccurrences(of: "Next ", with: ""))
                    .font(WatchFont.body)
                    .foregroundStyle(WatchColor.inkSecondary)
            }
            Spacer()
        }
        .animation(.default, value: remaining)
    }

    /// 104 pt, or 88 on the 40 mm where the full stack would otherwise push under the clock.
    private var ringSize: CGFloat { WatchMetric.isSmall ? 88 : 104 }

    private var progress: Double {
        guard let session, session.restTotal > 0 else { return 0 }
        return Double(remaining) / Double(session.restTotal)
    }

    /// "set 3 of 4 next": the on-deck set's position in its exercise.
    private var nextSetLine: String {
        guard let session, let index = session.onDeckIndex else { return "last set done" }
        let entry = session.exercises[index]
        guard let set = entry.sets.first(where: { !$0.isDone }) else { return "last set done" }
        let position = SetFormat.position(of: set, in: entry)
        return "set \(position.index) of \(position.count) next"
    }
}
