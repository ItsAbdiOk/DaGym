import GymCore
import SwiftData
import SwiftUI
import UIKit

/// The App Store screenshot build (`-dgScreenshots`, Debug only — `LaunchFlags.isScreenshotting`
/// is always false in Release). A throwaway in-memory store is filled with everything the shot
/// list in `docs/appstore/screenshots.md` needs, and `-dgScreenshotScreen <name>` opens one
/// screen directly so `scripts/screenshots.sh` never has to drive the UI. Without a screen name
/// the real `RootView` shell opens on the seeded store.
///
/// Distinct from `-dgScreen` (`DebugRoute`), which renders screens over `SampleData`'s static
/// fixtures: these screens read the store, so charts, PRs, the heatmap and the recovery map all
/// derive from the same eight weeks of logged sets.
enum ScreenshotScreen: String, CaseIterable {
    case home, workout, rest, progress, chart, records, consistency, recovery, routines, builder
    case library, exerciseDetail, settings, settingsData, milestones, body, coach, summary
    /// The cloud coach over the Coach tab, on a canned thread (`ScreenshotCoachChat`): the
    /// answer with its routine card, and the two-card second-opinion moment.
    case coachChat, coachReview, coachProgram, gymCard

    static var fromLaunchArguments: ScreenshotScreen? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-dgScreenshotScreen"), idx + 1 < args.count else { return nil }
        return ScreenshotScreen(rawValue: args[idx + 1])
    }

    /// Screens that show the workout that is mid-set. Every other screen leaves it out, since an
    /// unfinished workout makes `RootView` open with a "Resume Workout?" dialog on top.
    var needsInProgressWorkout: Bool { self == .workout || self == .rest }

    /// The canned chat thread the screen opens on, if it opens the chat at all.
    var coachChatThread: ((Date) -> CoachChatThread)? {
        switch self {
        case .coachChat: ScreenshotCoachChat.chatThread
        case .coachReview: ScreenshotCoachChat.reviewThread
        case .coachProgram: ScreenshotCoachProgram.thread
        default: nil
        }
    }
}

/// Fills the screenshot store. Everything is dated relative to `now` — 09:41 today — so the
/// status-bar override in `scripts/screenshots.sh` and the timestamps on screen agree.
@MainActor
enum ScreenshotMode {
    /// 09:41 today, Apple's marketing time, so "Today · 9:41" rows match the status bar.
    static var now: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
    }

    /// History is logged by an evening lifter (sessions end around 19:20): the newest one is
    /// then ~15 hours old at 09:41, close enough for the recovery map to show yesterday's legs
    /// still recovering rather than a body that is fresh all over.
    static var historyAnchor: Date {
        Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date()) ?? Date()
    }

    /// Everything the shot list needs on top of the Push/Pull/Legs trio: eight weeks of
    /// Push/Pull/Legs history, a bodyweight series with a goal, the milestones that history
    /// earns, a schedule that puts Push A on today, and Bench Press as the favourite so the
    /// exercise chart opens on it.
    static func seed(store: WorkoutStore, preferences: Preferences) {
        preferences.hasCompletedOnboarding = true
        preferences.weightUnit = .kg
        preferences.weeklyGoal = 3
        preferences.effortTrackingEnabled = true
        // The simulator has no iCloud account, so an enabled toggle shows a "sign in" warning
        // under it; off reads as the "no account needed" point the Settings shot is making.
        preferences.iCloudSyncEnabled = false
        // Eight hard weeks trip the deload suggestion; it would sit under the hero card on Home.
        preferences.deloadSnoozedUntil = now.addingTimeInterval(14 * 24 * 60 * 60)
        // The chat's key check is short-circuited by the flag (`CoachChatSettings.hasAPIKey`);
        // consent is the other half of "ready", so the Coach tab's entry card reads as live.
        preferences.coachChatConsentGiven = true
        SampleDataSeeder.seed(store: store, preferences: preferences, now: historyAnchor)
        // Marketing shots are the trained-in app, not a trial: no "Sample data · Clear" banner.
        preferences.sampleDataMode = false
        seedBodyweight(store: store, preferences: preferences)
        seedSchedule(store: store)
        // An active starter program, so the Train tab's Programs segment shows the active card
        // rather than only the starter list.
        if store.programs().isEmpty { store.adoptStarterPlan(.pushPullLegs, now: now) }
        // A gym card so the check-in sheet has a barcode and, with the pass identity bundled,
        // an Add to Wallet button under it.
        if store.gymCards().isEmpty {
            _ = store.addGymCard(name: "PureGym", value: "8412 3395 0071", symbology: .code128)
        }
        if let bench = benchPress(in: store), !bench.isFavorite { store.toggleFavorite(id: bench.id) }
        seedMilestones(store: store, preferences: preferences)
    }

    /// Milestones dated when the history would actually have earned them. The store's own
    /// `evaluateMilestones` scores the whole history at once, so run after seeding it stamps
    /// every badge with the last session's date; replaying the count/tonnage/streak tiers
    /// workout by workout spreads them across the eight weeks. The strength-ratio tiers still
    /// come from the store's pass at the end (their keys are the store's own).
    private static func seedMilestones(store: WorkoutStore, preferences: Preferences) {
        let calendar = preferences.trainingCalendar
        var earned: [String: Tier] = [:]
        var tonnage = 0.0
        var weeks: Set<Date> = []
        for (index, workout) in store.finishedWorkoutModelsNewestFirst().reversed().enumerated() {
            for set in (workout.exercises ?? []).flatMap({ $0.sets ?? [] }) where set.isCompleted {
                tonnage += set.weightKg * Double(set.reps)
            }
            if let week = calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start {
                weeks.insert(week)
            }
            let state = MilestoneState(
                workoutCount: index + 1, streakWeeks: weeks.count, lifetimeTonnageKg: tonnage,
                consistentWeeks: max(0, weeks.count - 1)
            )
            let earnedList = earned.map { (id: $0.key, tier: $0.value) }
            for achievement in Milestones.evaluate(state: state, earned: earnedList) {
                earned[achievement.id] = achievement.tier
                let tier = ["bronze", "silver", "gold"][achievement.tier.rawValue]
                store.context.insert(AchievementModel(
                    milestoneID: achievement.id, tier: tier, earnedAt: workout.startedAt,
                    workoutID: workout.id
                ))
            }
        }
        store.save()
        if let last = store.finishedWorkoutModelsNewestFirst().first {
            store.evaluateMilestones(for: last, weeklyGoal: preferences.weeklyGoal)
        }
    }

    /// Push A started 32 minutes ago: warm-ups and two working sets on the bench logged at
    /// 100 kg × 5, the third pre-filled at the same load so the plate chip reads for it. The
    /// bench rows are written outright rather than edited in place — the progression engine's
    /// own prescription (extra warm-ups, its rep target) is exactly what a marketing shot must
    /// not depend on. Ghost values come from the last logged session, as they would live.
    static func inProgressSession(store: WorkoutStore, preferences: Preferences) -> WorkoutSession {
        let pushA = store.routines().first { $0.name == "Push A" }
        let session = store.startWorkout(routineID: pushA?.id, calendar: preferences.trainingCalendar)
        session.effortScale = preferences.effortScale
        // Wall-clock relative, not 09:41-relative: the elapsed timer counts from the real clock.
        session.startedAt = Date().addingTimeInterval(-32 * 60 - 18)
        // The model carries its own start (`finish` measures duration from it), so move both.
        if let workoutID = session.workoutID {
            store.fetchWorkoutModel(id: workoutID)?.startedAt = session.startedAt
        }
        if !session.exercises.isEmpty {
            let previous = session.exercises[0].sets.last { $0.kind == .working }
            let ghostKg = previous?.previousWeightKg ?? 97.5
            let ghostReps = previous?.previousReps ?? 8
            session.exercises[0].sets = [
                SetEntry(kind: .warmup, weightKg: 40, reps: 10, isDone: true),
                SetEntry(kind: .warmup, weightKg: 60, reps: 5, isDone: true),
                SetEntry(
                    weightKg: 100, reps: 5, effort: Effort(rpe: 8), isDone: true,
                    previousWeightKg: ghostKg, previousReps: ghostReps
                ),
                SetEntry(
                    weightKg: 100, reps: 5, effort: Effort(rpe: 8.5), isDone: true,
                    previousWeightKg: ghostKg, previousReps: ghostReps
                ),
                SetEntry(weightKg: 100, reps: 5, previousWeightKg: ghostKg, previousReps: ghostReps)
            ]
        }
        session.markLoggedSetsAsSeen()
        store.sync(session: session)
        return session
    }

    /// Every remaining set logged as prescribed, for the Summary shot: a finished Push A rather
    /// than one abandoned after the bench.
    static func completeEverything(in session: WorkoutSession) {
        for exerciseIndex in session.exercises.indices {
            for setIndex in session.exercises[exerciseIndex].sets.indices {
                session.exercises[exerciseIndex].sets[setIndex].isDone = true
                if session.exercises[exerciseIndex].sets[setIndex].effort == nil,
                   session.exercises[exerciseIndex].sets[setIndex].kind != .warmup {
                    session.exercises[exerciseIndex].sets[setIndex].effort = Effort(rpe: 8)
                }
            }
        }
    }

    /// The rest after bench set 2 with 1:32 of 2:30 left, the way the pill looks mid-workout.
    static func startRest(in session: WorkoutSession) {
        guard let last = session.exercises.first?.sets.lastIndex(where: \.isDone) else { return }
        session.startRest(seconds: 150, after: 0, set: last)
        session.restRemaining = 92
        session.restEndDate = Date().addingTimeInterval(92)
    }

    /// The chat archive holds exactly the thread the screen wants — or nothing, so every other
    /// screen's Home shows "Week review ready" rather than a review thread. The archive is the
    /// screenshot build's own temp directory (`CoachChatArchive.standard()` redirects there),
    /// never the app's.
    static func seedCoachChat(for screen: ScreenshotScreen?) {
        guard let archive = CoachChatArchive.standard() else { return }
        try? FileManager.default.removeItem(at: archive.directory)
        guard let thread = screen?.coachChatThread?(historyAnchor) else { return }
        try? archive.save(thread)
    }

    static func benchPress(in store: WorkoutStore) -> ExerciseInfo? {
        store.routines().first { $0.name == "Push A" }?.exercises.first
    }

    /// Ten weeks of weigh-ins easing from 84.0 kg towards an 80 kg goal.
    private static func seedBodyweight(store: WorkoutStore, preferences: Preferences) {
        preferences.bodyweightGoalKg = 80
        let calendar = Calendar.current
        for weekAgo in stride(from: 9, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -weekAgo * 7 + 1, to: now) else { continue }
            let wobble = weekAgo.isMultiple(of: 2) ? 0.2 : -0.1
            let kg = 82.2 + Double(weekAgo) * 0.2 + wobble
            _ = store.logBodyweight(kg: (kg * 10).rounded() / 10, date: min(date, now))
        }
        store.save()
    }

    /// Push A · Pull B · Legs across the week, with Push A moved onto today so Home shows a
    /// scheduled session rather than a rest day.
    private static func seedSchedule(store: WorkoutStore) {
        let routines = store.routines()
        func id(_ name: String) -> UUID? { routines.first { $0.name == name }?.id }
        var schedule = WeeklySchedule()
        let today = Weekday(rawValue: Calendar.current.component(.weekday, from: now)) ?? .monday
        let plan: [(Weekday, String)] = [(.monday, "Push A"), (.wednesday, "Pull B"), (.friday, "Legs")]
        for (day, name) in plan where day != today {
            if let routineID = id(name) { schedule.setRoutines([routineID], on: day) }
        }
        if let pushA = id("Push A") { schedule.setRoutines([pushA], on: today) }
        store.saveSchedule(schedule)
    }
}

/// Builds the screenshot store and environment, then renders the requested screen (or the
/// app shell). Mirrors `DebugRootView`, plus the Health services `RootView` would provide.
struct ScreenshotRootView: View {
    let screen: ScreenshotScreen?

    private let preferences: Preferences
    @State private var container: ModelContainer?
    @State private var store: WorkoutStore?
    @State private var session: WorkoutSession?
    @State private var summary: WorkoutSummary?
    @State private var healthSync: HealthSyncService?
    @State private var healthInsights: HealthInsightsService?

    init(screen: ScreenshotScreen?) {
        self.screen = screen
        UIView.setAnimationsEnabled(false)
        // A private, wiped suite: every launch starts from the same preferences.
        let suiteName = "dev.abdirahmanmohamed.dagym.screenshots"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        preferences = Preferences(suite: UserDefaults(suiteName: suiteName) ?? .standard)
    }

    var body: some View {
        Group {
            if let container, let store, let healthSync, let healthInsights {
                ScreenshotScreenView(screen: screen, session: session, summary: summary)
                    .environment(store)
                    .environment(preferences)
                    .environment(healthSync)
                    .environment(healthInsights)
                    .environment(CoachServices.make(preferences: preferences))
                    .modelContainer(container)
            } else {
                AmbientWash()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let resolved = try? ModelContainer.dagym(inMemory: true) else { return }
        ExerciseSeeder.seedIfNeeded(context: resolved.mainContext)
        let newStore = WorkoutStore(context: resolved.mainContext)
        // The Push/Pull/Legs trio every shot is built on (`SampleDataSeeder.seed` would write
        // the same three; explicit here so the shot list's dependency is visible).
        RoutineSeeder.seedStarters(RoutineSeeder.pushPullLegsNames, store: newStore)
        EquipmentSeeder.seedIfNeeded(store: newStore, unit: preferences.weightUnit)
        WorkoutSession.defaultWarmupGrid = { [weak newStore] exercise in
            guard let newStore else { return .step(max(exercise.incrementKg, 0.5)) }
            return newStore.loadGrid(for: exercise, equipment: newStore.activeEquipment())
        }
        ScreenshotMode.seed(store: newStore, preferences: preferences)
        ScreenshotMode.seedCoachChat(for: screen)
        if screen?.needsInProgressWorkout == true || screen == .summary {
            let live = ScreenshotMode.inProgressSession(store: newStore, preferences: preferences)
            if screen == .rest { ScreenshotMode.startRest(in: live) }
            if screen == .summary {
                ScreenshotMode.completeEverything(in: live)
                summary = newStore.finish(session: live, weeklyGoal: preferences.weeklyGoal)
            }
            session = live
        }
        healthSync = HealthSyncService(workoutStore: newStore, preferences: preferences)
        healthInsights = HealthInsightsService(workoutStore: newStore, preferences: preferences)
        container = resolved
        store = newStore
    }
}

/// One shot-list screen on the seeded store, hosted the way the shipping app hosts it (tab
/// bar, navigation stack or sheet) so the chrome in the shot is the real thing.
private struct ScreenshotScreenView: View {
    let screen: ScreenshotScreen?
    let session: WorkoutSession?
    let summary: WorkoutSummary?

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    var body: some View {
        content.preferredColorScheme(preferences.appearance.colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case nil, .home:
            RootView()
        case .workout, .rest:
            if let session { ActiveWorkoutView(session: session, onFinish: { _ in }) }
        case .summary:
            if let session, let summary {
                WorkoutSummaryView(summary: summary, title: session.title, onDone: {})
            }
        case .progress:
            tabbed(.you) { HistoryTabView() }
        case .chart:
            tabbed(.you) { HistoryTabView() }.sheet(isPresented: .constant(true)) { ProgressScreen() }
        case .records:
            tabbed(.you) { NavigationStack { PersonalRecordsView() } }
        case .consistency:
            tabbed(.you) { NavigationStack { ConsistencyView() } }
        case .milestones:
            tabbed(.you) { NavigationStack { MilestonesView() } }
        case .recovery:
            RootView().sheet(isPresented: .constant(true)) { RecoveryMapView() }
        case .body:
            RootView().sheet(isPresented: .constant(true)) { BodyView() }
        case .routines:
            tabbed(.train) { RoutinesTabView(onStart: { _ in }) }
        case .builder:
            RoutineBuilderView(routineID: store.routines().first { $0.name == "Push A" }?.id, onDone: {})
        case .library:
            tabbed(.you) { NavigationStack { LibraryView() } }
        case .exerciseDetail:
            tabbed(.you) {
                NavigationStack {
                    if let bench = ScreenshotMode.benchPress(in: store) {
                        ExerciseDetailView(exercise: bench)
                    }
                }
            }
        case .settings:
            RootView().sheet(isPresented: .constant(true)) { SettingsView() }
        case .gymCard:
            RootView().sheet(isPresented: .constant(true)) { GymCardSheet() }
        case .settingsData:
            RootView().sheet(isPresented: .constant(true)) { ScreenshotDataSettingsView() }
        case .coach:
            tabbed(.you) { CoachView() }
        case .coachChat, .coachReview, .coachProgram:
            // The chat and program shots are the card's rows and reasons; the review shot is
            // two cards side by side, which only fit closed.
            tabbed(.you) { CoachView() }
                .fullScreenCover(isPresented: .constant(true)) { CoachChatView() }
                .environment(\.coachDraftCardsExpanded, screen != .coachReview)
        }
    }

    /// The system tab bar around one tab, as `DebugScreenView.tabbed` does for `-dgScreen`.
    private func tabbed<Content: View>(
        _ selected: DGTab, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        TabView(selection: .constant(selected)) {
            ForEach(DGTab.allCases, id: \.self) { tab in
                Tab(value: tab) {
                    if tab == selected { content() } else { AmbientWash() }
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(DGColor.coral)
    }
}

/// Settings opened at its Data section: the sync, export/import and reset cards in the same
/// container `SettingsView` uses, without the eight cards that sit above them on the real
/// screen (the shot makes the "no account, export anytime" point, and those are off-screen).
private struct ScreenshotDataSettingsView: View {
    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    Text("Settings")
                        .font(DGFont.title1)
                        .foregroundStyle(DGColor.ink1)
                    ICloudSettingsSection()
                    DataSettingsSection()
                    ImportSettingsSection()
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
    }
}
