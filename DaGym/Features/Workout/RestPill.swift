import SwiftUI

/// The prototype's floating rest pill: a near-black strip (`#1c1917` at .9, radius 22) with a
/// depleting ring, the countdown, "Next: 72.5 × 8 · Barbell Bench Press", and "+30s" / "Skip"
/// pills. The same dark strip in both schemes — it is a fixed dark surface, so the white text
/// stays readable either way.
struct RestPill: View {
    var remaining: Int
    var total: Int
    /// "Next <exercise name>" / "Last set done" — used as-is when `nextWeightKg`/`nextReps`
    /// are nil; otherwise those raw values are formatted in the user's unit instead.
    var nextLabel: String
    var nextWeightKg: Double?
    var nextReps: Int?
    /// The exercise the next set belongs to, appended after the numbers when we have them.
    var nextExerciseName: String?
    var onAddThirty: () -> Void
    var onSkip: () -> Void

    @Environment(Preferences.self) private var preferences

    static let ink = Color(hex: 0x1C1917)
    private static let shape = RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)

    private var resolvedNextLabel: String {
        if let nextWeightKg, let nextReps {
            let numbers = "Next: \(preferences.formatWeight(kg: nextWeightKg)) × \(nextReps)"
            guard let nextExerciseName, !nextExerciseName.isEmpty else { return numbers }
            return "\(numbers) · \(nextExerciseName)"
        }
        return nextLabel
    }

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            RestRing(remaining: remaining, total: total, size: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(WorkoutSession.clock(remaining))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(resolvedNextLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: DGSpace.s2)
            pill("+30s", action: onAddThirty)
                .accessibilityLabel("Add 30 seconds")
            pill("Skip", action: onSkip)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, DGSpace.s3)
        .background(Self.ink.opacity(0.92), in: Self.shape)
        .background(.ultraThinMaterial, in: Self.shape)
        .shadow(color: .black.opacity(0.28), radius: 17, y: 7)
        .dgDenseType()
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(minHeight: 32)
                .background(.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.dgControl)
    }
}

/// Compact ring + time only, for the scrolled state.
struct RestPillCompact: View {
    var remaining: Int
    var total: Int

    var body: some View {
        ZStack {
            RestRing(remaining: remaining, total: total, size: 48)
            Text(WorkoutSession.clock(remaining))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 48, height: 48)
        .background(RestPill.ink.opacity(0.92), in: Circle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rest, \(WorkoutSession.clock(remaining)) remaining")
    }
}

/// The rest pill, in its own view so that it — and only it — depends on the session's rest
/// state. `WorkoutSession.tickRest()` writes `restRemaining` once a second; when the parent
/// read it, that tick re-rendered the whole screen (muscle map, stat strip, every card).
struct RestPillSection: View {
    var session: WorkoutSession

    /// The exercise "Next: 72.5 × 8" belongs to. `rest.exerciseName` is the set just logged; a
    /// plain exercise's next set is its own, but a superset's next round starts on the group's
    /// first member, so the name is left off there rather than named wrong.
    private var nextExerciseName: String? {
        let name = session.rest.exerciseName
        guard let entry = session.exercises.first(where: { $0.exercise.name == name }),
              entry.supersetGroup == nil else { return nil }
        return name
    }

    var body: some View {
        if session.isResting {
            RestPill(
                remaining: session.restRemaining, total: session.restTotal,
                nextLabel: session.restNextLabel, nextWeightKg: session.restNextWeightKg,
                nextReps: session.restNextReps, nextExerciseName: nextExerciseName,
                onAddThirty: { session.adjustRest(by: 30) }, onSkip: { session.skipRest() }
            )
            .dgTransition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// `RestPillSection`'s counterpart for the condensed chrome.
struct RestPillCompactSection: View {
    var session: WorkoutSession

    var body: some View {
        if session.isResting {
            RestPillCompact(remaining: session.restRemaining, total: session.restTotal)
        }
    }
}

/// A white conic ring that empties as the rest runs down, on the pill's dark ink.
private struct RestRing: View {
    var remaining: Int
    var total: Int
    var size: CGFloat

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(remaining) / Double(total)
    }

    private var isFinal: Bool { remaining > 0 && remaining <= 3 }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .dgAnimation(DGMotion.timer, value: remaining)
    }

    private var ringColor: Color { isFinal ? DGColor.coral : .white }
}

#Preview {
    VStack(spacing: DGSpace.s4) {
        RestPill(
            remaining: 94, total: 150, nextLabel: "", nextWeightKg: 72.5, nextReps: 8,
            nextExerciseName: "Barbell Bench Press", onAddThirty: {}, onSkip: {}
        )
        RestPillCompact(remaining: 2, total: 60)
    }
    .padding()
    .background(DGColor.bgBase)
    .environment(Preferences())
}
