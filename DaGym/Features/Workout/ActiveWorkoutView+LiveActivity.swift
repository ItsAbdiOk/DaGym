import SwiftUI

extension View {
    /// Wires the rest-timer Live Activity + end-of-rest notification lifecycle to `session`, and
    /// takes the activity down again when the workout screen goes away for any reason.
    func restLiveActivity(session: WorkoutSession, onSessionMutation: @escaping () -> Void) -> some View {
        modifier(RestLiveActivityModifier(session: session, onSessionMutation: onSessionMutation))
    }
}

private struct RestLiveActivityModifier: ViewModifier {
    let session: WorkoutSession
    let onSessionMutation: () -> Void

    @Environment(Preferences.self) private var preferences

    func body(content: Content) -> some View {
        content
            .task {
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
            .onDisappear { RestActivityController.shared.endNow() }
    }
}
