import SwiftData
import SwiftUI

/// App shell: switches between the five tabs and presents the active
/// workout (and its summary) full-screen when a session is started.
struct RootView: View {
    @Environment(WorkoutStore.self) private var store
    @State private var tab = DGTab.today
    @State private var routine: RoutineInfo?
    @State private var session: WorkoutSession?
    @State private var summaryItem: SummaryPresentation?
    @State private var showingBackfill = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            DGTabBar(selected: $tab)
                .padding(.bottom, 8)
        }
        .task { refreshRoutine() }
        .onChange(of: tab) { _, _ in refreshRoutine() }
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(onFreestyle: startBackfillFreestyle, onRoutine: startBackfillRoutine)
        }
        .fullScreenCover(item: $session) { activeSession in
            ActiveWorkoutView(session: activeSession, onFinish: finish)
        }
        .fullScreenCover(item: $summaryItem) { item in
            WorkoutSummaryView(
                summary: item.summary, title: item.title, onShare: {}, onDone: { summaryItem = nil }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .today:
            HomeView(
                routine: routine, onStart: startFromScheduledRoutine, onFreestyle: startFreestyle,
                onBackfill: { showingBackfill = true }, onSeeRecovery: {}
            )
        case .routines:
            RoutinesTabView(onStart: startWorkout)
        case .progress:
            HistoryTabView()
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

    private func refreshRoutine() {
        routine = store.routines().first
    }

    private func startFromScheduledRoutine() {
        guard let routine else { return }
        startWorkout(routine)
    }

    private func startWorkout(_ routine: RoutineInfo) {
        session = store.startWorkout(routineID: routine.id)
    }

    private func startFreestyle() {
        session = store.startFreestyle()
    }

    private func startBackfillFreestyle(date: Date, durationMinutes: Int) {
        showingBackfill = false
        session = store.startBackfill(date: date, durationMinutes: durationMinutes, routineID: nil)
    }

    private func startBackfillRoutine(date: Date, durationMinutes: Int) {
        showingBackfill = false
        let routineID = store.routines().first?.id
        session = store.startBackfill(date: date, durationMinutes: durationMinutes, routineID: routineID)
    }

    private func finish(_ summary: WorkoutSummary) {
        let title = session?.title ?? "Workout"
        session = nil
        summaryItem = SummaryPresentation(summary: summary, title: title)
        refreshRoutine()
    }
}

/// Wraps a `WorkoutSummary` (not itself `Identifiable`) for `fullScreenCover(item:)`.
private struct SummaryPresentation: Identifiable {
    let id = UUID()
    let summary: WorkoutSummary
    let title: String
}

extension WorkoutSession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        RootView()
            .environment(WorkoutStore(context: container.mainContext))
            .modelContainer(container)
    } else {
        Text("Preview unavailable")
    }
}
