import SwiftUI

/// Home → active workout → summary, one screen at a time. The active workout replaces Home
/// rather than pushing, so the crown and swipes belong to the workout alone.
struct WatchContentView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ZStack {
            WatchColor.background.ignoresSafeArea()
            if store.summary != nil {
                SummaryView()
            } else if store.session != nil {
                ActiveWorkoutView()
            } else {
                HomeView()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: applyDebugScreen)
    }

    private func applyDebugScreen() {
        #if DEBUG
        WatchDebugScreens.apply(WatchLaunchFlags.screen, store: store)
        #endif
    }
}
