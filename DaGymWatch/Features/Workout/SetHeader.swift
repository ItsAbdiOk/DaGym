import GymCore
import SwiftUI

/// "Set 2 of 4" with the progress dots; the shape adds its qualifier ("Target 5+",
/// "Bodyweight", "Assisted", "· target 0:45"). Reads as one VoiceOver element.
struct SetHeader: View {
    var shape: SetShape
    var set: SetEntry
    var position: (index: Int, count: Int)
    var dotsDone: Int
    var dotsTotal: Int
    /// The plan's rep floor for an AMRAP row, captured when the session was built.
    var amrapTarget: Int?

    var body: some View {
        // The dots give way before the qualifier truncates on a narrow case.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                labels
                Spacer(minLength: 4)
                ProgressDots(done: dotsDone, total: dotsTotal)
            }
            HStack(spacing: 6) {
                labels
                Spacer(minLength: 0)
            }
        }
        .frame(height: 18)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(dotsDone) of \(dotsTotal) sets done")
    }

    private var labels: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(WatchFont.body)
                .foregroundStyle(WatchColor.inkSecondary)
                .fixedSize()
            if let qualifier {
                Text(qualifier)
                    .font(WatchFont.secondary)
                    .foregroundStyle(qualifierTint)
                    .fixedSize()
            }
        }
    }

    private var label: String {
        switch shape {
        case .warmup: "Warm-up \(position.index) of \(position.count)"
        case .timedHold:
            "Set \(position.index) of \(position.count) · target "
                + WorkoutSession.clock(set.targetSeconds ?? 0)
        case .cardio: "Set \(position.index) of \(position.count)"
        default: "Set \(position.index) of \(position.count)"
        }
    }

    private var qualifier: String? {
        switch shape {
        case .amrap: "Target \(amrapTarget ?? set.reps)+"
        case .bodyweight: "Bodyweight"
        case .assisted: "Assisted"
        default: nil
        }
    }

    private var qualifierTint: Color {
        shape == .amrap ? WatchColor.accent : WatchColor.inkTertiary
    }
}
