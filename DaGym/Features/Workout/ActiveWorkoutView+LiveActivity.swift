import SwiftUI

extension View {
    /// Wires the rest-timer Live Activity + end-of-rest notification lifecycle to `session`, and
    /// takes the activity down again when the view goes away for any reason. `isEnabled: false`
    /// leaves the view untouched, for a cover whose shell binds the activity itself so it can
    /// outlive the cover (`RootView`'s minimised workout).
    func restLiveActivity(
        session: WorkoutSession, isEnabled: Bool = true, onSessionMutation: @escaping () -> Void
    ) -> some View {
        modifier(RestLiveActivityModifier(
            session: session, isEnabled: isEnabled, onSessionMutation: onSessionMutation
        ))
    }
}

private struct RestLiveActivityModifier: ViewModifier {
    let session: WorkoutSession
    let isEnabled: Bool
    let onSessionMutation: () -> Void

    @Environment(Preferences.self) private var preferences

    func body(content: Content) -> some View {
        content
            .task {
                guard isEnabled else { return }
                RestActivityController.shared.bind(
                    to: session, weightUnit: { preferences.weightUnit },
                    theme: {
                        RestActivityTheme(
                            accent: preferences.accent.rawValue,
                            appearance: preferences.appearance.rawValue
                        )
                    },
                    onSessionMutation: onSessionMutation
                )
            }
            .onDisappear { if isEnabled { RestActivityController.shared.endNow() } }
    }
}
