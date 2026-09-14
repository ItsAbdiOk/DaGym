import GymCore
import SwiftUI

/// Screen 7 always-on: the numbers and nothing else — no buttons, no fills, accent only on
/// the live value. Raising the wrist restores the full screen in place. Same for the SE,
/// which has no always-on display but takes the same code path.
struct AlwaysOnView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences

    var body: some View {
        if let session = store.session, session.isResting {
            rest(session)
        } else if let session = store.session {
            active(session)
        }
    }

    private func active(_ session: WorkoutSession) -> some View {
        let unit = preferences.weightUnit
        let index = min(store.pageIndex, max(0, session.exercises.count - 1))
        let entry = session.exercises.indices.contains(index) ? session.exercises[index] : nil
        let set = entry?.sets.first { !$0.isDone }
        return VStack(spacing: 4) {
            if let entry, let set {
                let position = SetFormat.position(of: set, in: entry)
                SafeBandText(text: "\(entry.exercise.name) · set \(position.index) of \(position.count)")
            }
            Spacer()
            if let set {
                Text(SetFormat.weight(set.weightKg, unit: unit))
                    .font(WatchFont.value(44, weight: .bold))
                    .foregroundStyle(WatchColor.accent)
                Text("\(unit.symbol) × \(set.reps)")
                    .font(WatchFont.bodyMedium)
                    .foregroundStyle(WatchColor.ink)
                Text("Tap to log")
                    .font(WatchFont.secondary)
                    .foregroundStyle(WatchColor.inkTertiary)
            }
            Spacer()
            TimelineView(.everyMinute) { context in
                let elapsed = WorkoutSession.clock(session.elapsedSeconds(at: context.date))
                SafeBandText(text: "\(elapsed) · \(session.setsDone) sets")
            }
        }
        .padding(.horizontal, WatchMetric.gutter)
    }

    private func rest(_ session: WorkoutSession) -> some View {
        VStack(spacing: 4) {
            Spacer()
            ZStack {
                RingView(
                    progress: Double(session.restRemaining) / Double(max(session.restTotal, 1)), lineWidth: 6
                )
                VStack(spacing: 0) {
                    Text(WorkoutSession.clock(session.restRemaining))
                        .font(WatchFont.value(34, weight: .bold))
                        .foregroundStyle(WatchColor.accent)
                    Text("rest").font(WatchFont.secondary).foregroundStyle(WatchColor.inkSecondary)
                }
            }
            .frame(width: 104, height: 104)
            Text(RestLine.next(session: session, unit: preferences.weightUnit))
                .font(WatchFont.body)
                .foregroundStyle(WatchColor.ink)
            Spacer()
        }
        .padding(.horizontal, WatchMetric.gutter)
    }
}
