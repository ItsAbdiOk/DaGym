import SwiftUI

/// App shell: switches between the five tabs and presents the active
/// workout full-screen when a session is started from Home.
struct RootView: View {
    @State private var tab = DGTab.today
    @State private var session: WorkoutSession?

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            DGTabBar(selected: $tab)
                .padding(.bottom, 8)
        }
        .fullScreenCover(item: $session) { activeSession in
            ActiveWorkoutView(session: activeSession) {
                session = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .today:
            HomeView(
                routine: SampleData.pushA,
                onStart: { session = SampleData.makeSession() },
                onFreestyle: {},
                onBackfill: {},
                onSeeRecovery: {}
            )
        case .routines:
            EmptyState(
                symbol: "dumbbell",
                title: "No Routines Yet",
                message: "Build a routine to see it here and schedule it for your training days."
            )
        case .progress:
            EmptyState(
                symbol: "chart.bar",
                title: "No Progress Yet",
                message: "Finish a few workouts and your strength trends will show up here."
            )
        case .library:
            LibraryView()
        case .coach:
            EmptyState(
                symbol: "sparkles",
                title: "Coach Is Warming Up",
                message: "Log a couple of sessions and the coach will start offering suggestions."
            )
        }
    }
}

extension WorkoutSession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

#Preview {
    RootView()
}
