import GymCore
import SwiftUI

/// 3A: the rest timer in the stepper row's place. Header and dots hold still above it; only
/// this block changes, so the next set arrives where the last one was. Rests over 45 s
/// promote to `FullScreenRestView` instead.
struct InlineRestView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences
    var entry: WorkoutExerciseEntry

    static let maxInlineSeconds = 45

    var body: some View {
        let session = store.session
        VStack(spacing: 4) {
            if let logged = entry.sets.last(where: \.isDone) {
                Text("Logged \(loggedLine(logged))")
                    .font(WatchFont.secondary)
                    .foregroundStyle(WatchColor.inkSecondary)
            }
            Text(WorkoutSession.clock(session?.restRemaining ?? 0))
                .font(WatchFont.value(44, weight: .bold))
                .foregroundStyle(WatchColor.accent)
                .accessibilityLabel(restAccessibility(session?.restRemaining ?? 0))
            if let session {
                Text(RestLine.next(session: session, unit: preferences.weightUnit))
                    .font(WatchFont.body)
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            RestButtonRow()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func loggedLine(_ set: SetEntry) -> String {
        if entry.isTimed { return WorkoutSession.clock(set.durationSeconds ?? 0) }
        if entry.exercise.loggingStyle == .bodyweightReps, set.weightKg == 0 { return "\(set.reps) reps" }
        return SetFormat.weightByReps(set.weightKg, reps: set.reps, unit: preferences.weightUnit)
    }

    /// VoiceOver announces at 30 seconds and zero, never every second.
    private func restAccessibility(_ remaining: Int) -> String {
        remaining == 30 || remaining == 0 ? "\(remaining) seconds rest" : "Resting"
    }
}

/// "+30s" and "Skip", the only two rest controls.
struct RestButtonRow: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Button("+30s") { store.addRest(seconds: 30) }
                .font(WatchFont.bodyMedium)
                .foregroundStyle(WatchColor.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(WatchColor.card))
                .buttonStyle(.plain)
            Button("Skip") { store.skipRest() }
                .font(WatchFont.bodyMedium)
                .foregroundStyle(WatchColor.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(WatchColor.card))
                .buttonStyle(.plain)
        }
    }
}

/// "Next 100 × 5" / "Next Bench Press" / "Last set done", from the session's own rest state.
@MainActor
enum RestLine {
    static func next(session: WorkoutSession, unit: WeightUnit, withUnit: Bool = false) -> String {
        if let kg = session.restNextWeightKg, let reps = session.restNextReps {
            return withUnit
                ? "Next \(SetFormat.weightUnitByReps(kg, reps: reps, unit: unit))"
                : "Next \(SetFormat.weightByReps(kg, reps: reps, unit: unit))"
        }
        return session.restNextLabel
    }
}
