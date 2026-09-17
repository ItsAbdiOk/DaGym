import SwiftUI

extension View {
    /// The resume strip as the tab bar's bottom accessory while `session` is minimised.
    /// `isEnabled:` is iOS 26.1; the 26.0 target gets the accessory with empty content instead.
    @ViewBuilder
    func workoutResumeAccessory(session: WorkoutSession?, isShown: Bool, onResume: @escaping () -> Void)
        -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isShown) {
                if let session { WorkoutResumeBar(session: session, onResume: onResume) }
            }
        } else {
            tabViewBottomAccessory {
                if isShown, let session { WorkoutResumeBar(session: session, onResume: onResume) }
            }
        }
    }
}

/// The strip above the tab bar while a workout is minimised: the routine name, the elapsed
/// clock ticking (or the rest countdown while one runs), the set count and a "Resume" chevron.
/// The whole strip is one button — tapping anywhere puts the cover back. Drawn inside the tab
/// bar's own bottom accessory, so it shares the bar's glass and folds into it as the bar
/// minimises on scroll (`inline`), where only the name and the clock fit.
struct WorkoutResumeBar: View {
    var session: WorkoutSession
    var onResume: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: onResume) {
            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                HStack(spacing: DGSpace.s3) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DGColor.inkOnCoral)
                        .frame(width: 30, height: 30)
                        .background(DGColor.coral, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DGColor.ink1)
                            .lineLimit(1)
                        Text(detail(at: context.date))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(DGColor.ink3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DGSpace.s2)
                    if placement != .inline {
                        Text("Resume")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DGColor.coral)
                    }
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DGColor.coral)
                }
                .padding(.horizontal, DGSpace.s3)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Resume \(session.title), \(detail(at: context.date))")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.workoutResumeBar)
    }

    /// "25:14 · 4 of 19 sets", or "Rest 0:45 · 4 of 19 sets" while a rest runs — the rest
    /// timer lives in the session, so it counts down here exactly as it does on the cover.
    private func detail(at date: Date) -> String {
        let clock = session.isResting
            ? "Rest \(WorkoutSession.clock(session.restRemaining))"
            : WorkoutSession.clock(session.elapsedSeconds(at: date))
        let sets = placement == .inline
            ? "\(session.setsDone) / \(session.setsTotal)"
            : "\(session.setsDone) of \(session.setsTotal) sets"
        return "\(clock) · \(sets)"
    }
}
