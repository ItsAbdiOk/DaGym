import SwiftData
import SwiftUI

/// App shell: switches between the five tabs and presents the active
/// workout (and its summary) full-screen when a session is started.
struct RootView: View {
    /// True only for the single `RootView` that replaces `OnboardingFlow` right after
    /// `onComplete` — see the `.task` below for why that specific transition needs a startup
    /// delay that a normal cold launch straight into `RootView` does not.
    var justCompletedOnboarding = false

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var tab = DGTab.today
    @State private var routine: RoutineInfo?
    @State private var routines: [RoutineInfo] = []
    @State private var nextSessionText: String?
    @State private var session: WorkoutSession?
    @State private var summaryItem: SummaryPresentation?
    @State private var showingBackfill = false
    @State private var showRecovery = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            DGTabBar(selected: $tab)
                .padding(.bottom, 8)
        }
        .task {
            // `RootView` replacing `OnboardingFlow` mid-lifecycle (as opposed to a cold launch
            // mounting `RootView` fresh) tears down Onboarding's whole deep view hierarchy while
            // building this one, all in the same transaction — and fetching via a `#Predicate`
            // macro while AttributeGraph's background queue is still draining type-layout work
            // for that churn has been observed to crash (`WorkoutStore.routines()`,
            // `EXC_BREAKPOINT` inside `SwiftData`/`swift_conformsToProtocol`, confirmed with a
            // debugger attached — a real SwiftData/AttributeGraph race, not app logic). A cold
            // launch straight into `RootView` doesn't have a prior subtree to tear down and has
            // never reproduced this, so only pay the delay for the onboarding hand-off.
            if justCompletedOnboarding {
                try? await Task.sleep(for: .milliseconds(1500))
            }
            refreshRoutine()
        }
        .onAppear { startPendingRestTimerIfNeeded() }
        .onChange(of: tab) { _, _ in refreshRoutine() }
        .onOpenURL(perform: handleOpenURL)
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(
                routines: routines, onFreestyle: startBackfillFreestyle, onRoutine: startBackfillRoutine
            )
        }
        .sheet(isPresented: $showRecovery) {
            RecoveryMapView()
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
                routine: routine, nextSessionText: nextSessionText, onStart: startFromScheduledRoutine,
                onFreestyle: startFreestyle, onBackfill: { showingBackfill = true },
                onSeeRecovery: { showRecovery = true }, justCompletedOnboarding: justCompletedOnboarding
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
        routines = store.routines()
        routine = store.todaysRoutine()
        nextSessionText = Self.nextSessionText(store.nextSession())
    }

    /// "Next: Pull B · Thursday" for the rest-day card.
    private static func nextSessionText(_ next: (date: Date, routine: RoutineInfo)?) -> String? {
        guard let next else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "Next: \(next.routine.name) · \(formatter.string(from: next.date))"
    }

    private func startFromScheduledRoutine() {
        guard let routine else { return }
        startWorkout(routine)
    }

    private func startWorkout(_ routine: RoutineInfo) {
        session = store.startWorkout(routineID: routine.id)
        seedEffortScale()
    }

    private func startFreestyle() {
        session = store.startFreestyle()
        seedEffortScale()
    }

    private func startBackfillFreestyle(date: Date, durationMinutes: Int) {
        showingBackfill = false
        session = store.startBackfill(date: date, durationMinutes: durationMinutes, routineID: nil)
        seedEffortScale()
    }

    private func startBackfillRoutine(date: Date, durationMinutes: Int, routineID: UUID) {
        showingBackfill = false
        session = store.startBackfill(date: date, durationMinutes: durationMinutes, routineID: routineID)
        seedEffortScale()
    }

    /// New sessions start on the user's saved effort scale (`Preferences.effortScale` is the
    /// source of truth); the session keeps its own copy so `EffortPickerSheet`'s binding works.
    private func seedEffortScale() {
        session?.effortScale = preferences.effortScale
    }

    /// Control Center "Rest timer" hookup (`StartRestTimerIntent`/`PendingIntentAction`): if the
    /// intent opened the app, reuse the active session or start today's routine, then rest before
    /// its first on-deck set. `WorkoutSession.startRest` needs a real exercise/set to attach the
    /// rest to, so a freestyle session (no exercises yet) has nothing to rest before and this is
    /// a no-op — starting a routine covers the common case.
    private func startPendingRestTimerIfNeeded() {
        guard PendingIntentAction.consumeStartRestTimer() else { return }
        if session == nil {
            startFromScheduledRoutine()
        }
        guard let activeSession = session,
              let exerciseIndex = activeSession.onDeckIndex,
              let setIndex = activeSession.exercises[exerciseIndex].sets.firstIndex(where: { !$0.isDone })
        else { return }
        activeSession.startRest(seconds: preferences.defaultRestSeconds, after: exerciseIndex, set: setIndex)
    }

    /// Handles the `dagym://start?routine=<uuid>` deep link a synced calendar event opens
    /// (`CalendarSyncService`). No-op for any other host/URL.
    private func handleOpenURL(_ url: URL) {
        if url.host == "today" {
            tab = .today
            return
        }
        guard url.host == "start",
              let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "routine" })?.value,
              let routineID = UUID(uuidString: idString),
              let matched = store.routines().first(where: { $0.id == routineID })
        else { return }
        startWorkout(matched)
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
            .environment(Preferences())
            .modelContainer(container)
    } else {
        Text("Preview unavailable")
    }
}
