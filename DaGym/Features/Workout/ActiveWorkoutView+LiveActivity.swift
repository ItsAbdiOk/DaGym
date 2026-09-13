import SwiftUI

extension View {
    /// Wires the rest-timer Live Activity + end-of-rest notification lifecycle to `session`.
    /// Lead: add this one line to `ActiveWorkoutView.body`, alongside the existing
    /// `.task { session.onRestTick = handleRestTick; await runTimers() }`:
    ///
    ///     .restLiveActivity(session: session)
    func restLiveActivity(session: WorkoutSession) -> some View {
        modifier(RestLiveActivityModifier(session: session))
    }
}

private struct RestLiveActivityModifier: ViewModifier {
    let session: WorkoutSession

    func body(content: Content) -> some View {
        content.task { RestActivityController.shared.bind(to: session) }
    }
}
