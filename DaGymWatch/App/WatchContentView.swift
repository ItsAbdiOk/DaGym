import SwiftUI

/// Home → active workout → summary, one screen at a time. The active workout replaces Home
/// rather than pushing, so the crown and swipes belong to the workout alone.
struct WatchContentView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            WatchColor.background.ignoresSafeArea()
            #if DEBUG
            if let page = store.debugComplicationsPage {
                WatchComplicationsDebugView(page: page)
            } else {
                screens
            }
            #else
            screens
            #endif
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(WatchLaunchFlags.forcesLargestText ? .accessibility5 : dynamicTypeSize)
        .onAppear(perform: applyDebugScreen)
    }

    @ViewBuilder private var screens: some View {
        Group {
            if store.summary != nil {
                SummaryView()
            } else if store.session != nil {
                ActiveWorkoutView()
            } else {
                HomeView()
            }
        }
    }

    private func applyDebugScreen() {
        #if DEBUG
        WatchDebugScreens.apply(WatchLaunchFlags.screen, store: store)
        #endif
    }
}
