import Combine
import GymCore
import SwiftData
import SwiftUI

/// App shell: switches between the five tabs and presents the active
/// workout (and its summary) full-screen when a session is started.
struct RootView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = DGTab.today
    @State private var routine: RoutineInfo?
    @State private var routines: [RoutineInfo] = []
    @State private var nextSessionText: String?
    @State private var session: WorkoutSession?
    @State private var summaryItem: SummaryPresentation?
    @State private var showingBackfill = false
    @State private var showRecovery = false
    @State private var showingGymCard = false
    @State private var showingBody = false
    @State private var showingWeighIn = false
    @State private var pendingWorkoutStart: (() -> Void)?
    @State private var pendingPlanImport: PlanDocument?
    @State private var pendingPlanReport: PlanImportReport?
    @State private var planImportError: String?
    @State private var resumePrompt: UnfinishedWorkoutPrompt?

    var body: some View {
        tabs
        .task {
            refresh()
            // A Siri "start workout" hand-off above wins over the prompt: nothing to resume
            // while a session is already on screen.
            if session == nil { resumePrompt = UnfinishedWorkoutPrompt.newest(in: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)
        ) { _ in refresh() }
        .onChange(of: tab) { _, _ in
            Haptics.step()
            refreshRoutine()
        }
        // Deliberately *not* the full `refresh()`: `changeToken` bumps on every logged set, and
        // `WidgetSnapshotWriter.refresh` behind it is a whole-history fetch plus a streak
        // recompute — a visible hitch on every tap once history is large. The widget is already
        // written on finish, routine saves and schedule saves, which is when it can change.
        .onChange(of: store.changeToken) { _, _ in refreshRoutine() }
        .onChange(of: PendingIntentHandoff.shared.pending) { _, _ in runPendingIntents() }
        .confirmationDialog(
            "Resume Workout?", isPresented: resumePromptBinding, titleVisibility: .visible,
            presenting: resumePrompt
        ) { prompt in
            Button("Resume \(prompt.title)") { resumeUnfinished(prompt) }
            Button("Discard", role: .destructive) { discardUnfinished(prompt) }
            // Tapping outside the dialog already dismisses it, and there was no way back to the
            // workout afterwards — it simply sat there until the launch purge ate it. Saying
            // "Not now" out loud is the honest version of that, and the workout now survives:
            // `purgeUnfinished` never deletes one with sets in it, so it is offered again.
            Button("Not now", role: .cancel) { resumePrompt = nil }
        } message: { prompt in
            Text(prompt.detail)
        }
        .onOpenURL(perform: handleOpenURL)
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(
                routines: routines, onFreestyle: startBackfillFreestyle, onRoutine: startBackfillRoutine
            )
        }
        .sheet(isPresented: $showingGymCard) {
            GymCardSheet()
        }
        .sheet(isPresented: $showRecovery) {
            RecoveryMapView()
        }
        .sheet(isPresented: $showingBody) {
            BodyView()
        }
        .sheet(isPresented: $showingWeighIn, onDismiss: runPendingWorkoutStart) {
            BodyweightSheet()
        }
        .sheet(item: $pendingPlanImport) { document in
            PlanImportPreviewSheet(
                document: document, report: pendingPlanReport ?? PlanImportReport(),
                onConfirm: { confirmPlanImport(document) }, onCancel: { pendingPlanImport = nil }
            )
        }
        .alert(
            "Couldn't Import That Plan", isPresented: planImportErrorBinding,
            actions: {}, message: { Text(planImportError ?? "") }
        )
        .fullScreenCover(item: $session) { activeSession in
            ActiveWorkoutView(session: activeSession, onFinish: finish)
        }
        .fullScreenCover(item: $summaryItem) { item in
            WorkoutSummaryView(
                summary: item.summary, title: item.title, onShare: {}, onDone: { summaryItem = nil }
            )
        }
    }

    /// Re-reads everything this shell derives from the store, then acts on any Siri / Control
    /// Center hand-off — in that order, so the flag is never consumed against a routine that
    /// hasn't loaded yet. Runs on first mount, every return to the foreground (a warm launch from
    /// an intent lands here, not in `.task`) and at midnight, when today's routine changes.
    private func refresh() {
        refreshRoutine()
        WidgetSnapshotWriter.refresh(store: store, preferences: preferences)
        // The calendar sync writes a rolling 14-day window, and used to run only from the
        // Schedule and Settings screens — so a lifter who set their plan and never went back
        // had their calendar simply stop 14 days later. Running it here means launch, every
        // foreground and midnight all push the window forward, and a routine renamed or
        // deleted elsewhere has its events corrected on the next foreground.
        CalendarSyncCoordinator.syncInBackground(store: store, preferences: preferences)
        runPendingIntents()
    }

    /// Acts on everything queued in `PendingIntentHandoff`. Called from the first mount, every
    /// foreground, and directly from the `onChange` below — so an intent that lands after the
    /// refresh has already run is still honoured immediately.
    private func runPendingIntents() {
        for action in PendingIntentHandoff.consume(routineLoaded: true) {
            switch action {
            case .startWorkout: startPendingWorkout()
            case .startRestTimer: startPendingRestTimer()
            case .showGymCard: showingGymCard = true
            }
        }
    }

    private func refreshRoutine() {
        routines = store.routines()
        routine = store.todaysRoutine()
        nextSessionText = Self.nextSessionText(store.nextSession())
    }

    private var resumePromptBinding: Binding<Bool> {
        Binding(get: { resumePrompt != nil }, set: { if !$0 { resumePrompt = nil } })
    }

    private func resumeUnfinished(_ prompt: UnfinishedWorkoutPrompt) {
        resumePrompt = nil
        guard let resumed = store.resumeSession(for: prompt.id) else { return }
        session = resumed
        seedEffortScale()
    }

    private func discardUnfinished(_ prompt: UnfinishedWorkoutPrompt) {
        resumePrompt = nil
        store.deleteWorkout(id: prompt.id)
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
        beginWorkout {
            session = store.startWorkout(routineID: routine.id)
            seedEffortScale()
        }
    }

    private func startFreestyle() {
        beginWorkout {
            session = store.startFreestyle()
            seedEffortScale()
        }
    }

    /// When `preferences.weighInBeforeWorkout` is on, shows the (skippable — swipe to dismiss)
    /// `BodyweightSheet` before `start` runs; otherwise starts immediately (OpenGym parity 18).
    private func beginWorkout(_ start: @escaping () -> Void) {
        guard preferences.weighInBeforeWorkout else {
            start()
            return
        }
        pendingWorkoutStart = start
        showingWeighIn = true
    }

    private func runPendingWorkoutStart() {
        let start = pendingWorkoutStart
        pendingWorkoutStart = nil
        start?()
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

    /// Control Center "Rest timer" hookup (`StartRestTimerIntent`/`PendingIntentAction`): the
    /// intent opened the app, so reuse the active session or start today's routine, then rest
    /// before its first on-deck set. `WorkoutSession.startRest` needs a real exercise/set to
    /// attach the rest to, so a freestyle session (no exercises yet) has nothing to rest before
    /// and this is a no-op — starting a routine covers the common case.
    private func startPendingRestTimer() {
        // "Default rest: Off" means no rest timer anywhere, this intent included.
        guard preferences.defaultRestSeconds > 0 else { return }
        if session == nil {
            startFromScheduledRoutine()
        }
        guard let activeSession = session,
              let exerciseIndex = activeSession.onDeckIndex,
              let setIndex = activeSession.exercises[exerciseIndex].sets.firstIndex(where: { !$0.isDone })
        else { return }
        activeSession.startRest(seconds: preferences.defaultRestSeconds, after: exerciseIndex, set: setIndex)
    }

    /// "Start today's workout" Siri Shortcut hookup (`StartWorkoutIntent`/
    /// `PendingWorkoutIntentAction`): the intent opened the app, so if nothing is already in
    /// progress, start today's scheduled routine — same as tapping "Start" on Home. Leaves an
    /// already-active session alone rather than replacing it.
    private func startPendingWorkout() {
        guard session == nil else { return }
        startFromScheduledRoutine()
    }

    /// Handles the `dagym://start?routine=<uuid>` deep link a synced calendar event opens
    /// (`CalendarSyncService`), and a `.gymplan` file opened from Messages/AirDrop/Files (plan.md
    /// §6.8) — the latter loads and previews it via `PlanImportPreviewSheet` rather than acting
    /// immediately. No-op for any other host/URL.
    private func handleOpenURL(_ url: URL) {
        if url.isFileURL, url.pathExtension.lowercased() == "gymplan" {
            Task { await loadPlanImport(url: url) }
            return
        }
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
        // A calendar event tapped mid-workout must not replace the running session: `startWorkout`
        // would overwrite `session`, and the old `WorkoutSession`'s unsaved sets would go with it.
        guard session == nil else { return }
        startWorkout(matched)
    }

    private func finish(_ summary: WorkoutSummary) {
        let title = session?.title ?? "Workout"
        session = nil
        summaryItem = SummaryPresentation(summary: summary, title: title)
        refreshRoutine()
    }

    // MARK: - Plan import (plan.md §6.8)

    private var planImportErrorBinding: Binding<Bool> {
        Binding(get: { planImportError != nil }, set: { if !$0 { planImportError = nil } })
    }

    private func loadPlanImport(url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            // `sanitised()` is not optional politeness: a `.gymplan` arrives from someone else's
            // device and is written straight into routines, programs and custom exercises. Every
            // clamp in `PlanSanitizing` only runs because of this call.
            let document = try await Task.detached(priority: .userInitiated) {
                try PlanCodec.decode(data).sanitised()
            }.value
            pendingPlanReport = PlanShareService.importPlan(
                document: document, context: store.context, preview: true
            )
            pendingPlanImport = document
        } catch let error as PlanCodec.CodecError {
            planImportError = Self.message(for: error)
        } catch {
            planImportError = "That file isn't a valid DaGym plan."
        }
    }

    private static func message(for error: PlanCodec.CodecError) -> String {
        switch error {
        case .unsupportedFormatVersion:
            return "That plan was made by a newer version of DaGym. Update the app and try again."
        case .decodingFailed:
            return "That file isn't a valid DaGym plan."
        }
    }

    private func confirmPlanImport(_ document: PlanDocument) {
        PlanShareService.importPlan(document: document, context: store.context)
        pendingPlanImport = nil
        refreshRoutine()
    }
}

/// The app's five root tabs in Apple's own tab bar: Liquid Glass, its own safe-area inset
/// (screens no longer pad for a floating bar) and minimising as content scrolls down under it.
private extension RootView {
    var tabs: some View {
        TabView(selection: $tab) {
            Tab(value: DGTab.today) {
                HomeView(
                    routine: routine, nextSessionText: nextSessionText, onStart: startFromScheduledRoutine,
                    onFreestyle: startFreestyle, onBackfill: { showingBackfill = true },
                    onSeeRecovery: { showRecovery = true }, onOpenBody: { showingBody = true }
                )
            } label: { tabLabel(.today) }
            Tab(value: DGTab.routines) {
                RoutinesTabView(onStart: startWorkout)
            } label: { tabLabel(.routines) }
            Tab(value: DGTab.progress) { HistoryTabView() } label: { tabLabel(.progress) }
            Tab(value: DGTab.library) { LibraryView() } label: { tabLabel(.library) }
            Tab(value: DGTab.coach) { CoachView() } label: { tabLabel(.coach) }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(DGColor.coral) // the system bar's selected tint follows the accent theme
    }

    /// `DaGymUITests` taps these identifiers, so they ride on each tab's label.
    func tabLabel(_ tab: DGTab) -> some View {
        Label(tab.title, systemImage: tab.symbol)
            .accessibilityIdentifier(tab.accessibilityID)
    }
}

/// What the launch-time Resume/Discard prompt shows for the newest workout a crash or
/// force-quit left unfinished (anything older than a day was already purged at launch).
struct UnfinishedWorkoutPrompt: Identifiable, Equatable {
    let id: UUID
    let title: String
    let startedAt: Date
    let setsDone: Int

    /// "Started 25 min ago · 3 sets logged"
    var detail: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let started = formatter.localizedString(for: startedAt, relativeTo: Date())
        let sets = setsDone == 1 ? "1 set logged" : "\(setsDone) sets logged"
        return "Started \(started) · \(sets)"
    }

    /// The newest unfinished workout, or `nil` when there is nothing to resume.
    @MainActor
    static func newest(in store: WorkoutStore) -> UnfinishedWorkoutPrompt? {
        guard let model = store.unfinishedWorkouts().first else { return nil }
        let setsDone = (model.exercises ?? []).flatMap { $0.sets ?? [] }.filter(\.isCompleted).count
        return UnfinishedWorkoutPrompt(
            id: model.id, title: model.title.isEmpty ? "Workout" : model.title, startedAt: model.startedAt,
            setsDone: setsDone
        )
    }
}

/// `sheet(item:)` needs `Identifiable`; a document's export timestamp is a fine key since two
/// files opened back-to-back are always distinguishable by when they were made.
extension PlanDocument: @retroactive Identifiable {
    public var id: Date { exportedAt }
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
