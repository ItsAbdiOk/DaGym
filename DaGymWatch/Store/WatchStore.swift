import Foundation
import GymCore
import os
import SwiftData

/// What Home shows: today's routine (or the routine list on a rest day), the streak and the
/// next planned day. Rebuilt by `WatchStore.refreshHome()`.
struct WatchHomeState {
    var todaysRoutine: RoutineInfo?
    /// "Bench Press 4×5" per exercise of today's routine.
    var todaysLines: [(name: String, sets: String)] = []
    var routines: [RoutineInfo] = []
    var streakWeeks = 0
    var nextLabel: String?
    /// An unfinished workout this wrist may pick up (see `WatchStore.resumeGate`).
    var resumableWorkoutID: UUID?
    /// Where the resumable workout was started — `WatchStore.sourceDevice` for one of ours.
    var resumableSourceDevice: String?
    /// An unfinished workout that is live on the iPhone right now — shown, never offered.
    var inProgressElsewhereTitle: String?
    /// Workouts still open on this watch — the Settings sync row's "queued" count. Read here
    /// so the row doesn't fetch on every render.
    var unfinishedCount = 0
}

/// The watch's front door to the shared `WorkoutStore`. Everything that persists — building
/// today's session with the same prescription the phone would give, syncing every logged set,
/// finishing with PR detection and progression commit — goes through the phone's own store
/// code, compiled into this target. This type only adds what the wrist needs on top: the
/// Home state, the one-second tick, the HealthKit workout session that keeps the app alive
/// with the wrist down, the live PR preview card and the complication snapshot.
///
/// Split by concern: lifecycle (`+Lifecycle`), the tick and rest-end repeat (`+Tick`), the
/// complication snapshot and the CloudKit remote-change observer (`+Snapshot`), logging and
/// records (`+Logging`).
@MainActor
@Observable
final class WatchStore {
    /// What `WorkoutModel.sourceDevice` says for a workout started here. The shared start
    /// stamps "iPhone"; History groups and labels workouts by this, and the resume gate and
    /// HealthKit recovery both key on it.
    static let sourceDevice = "Apple Watch"

    static let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

    let store: WorkoutStore
    let preferences: WatchPreferences
    let runtime: WatchWorkoutRuntime
    /// The complication snapshot: rebuilt from the store at Home refresh, spliced on rest.
    let snapshots: WatchSnapshotWriter

    var home = WatchHomeState()
    /// False when the store opened without CloudKit (no account, or the container refused) —
    /// the Settings sync row says "iCloud off" instead of implying the phone will hear from us.
    var isCloudSyncOn = true
    var session: WorkoutSession?
    var summary: WorkoutSummary?
    /// The title of the session `summary` describes — what was actually done, which is not
    /// always today's routine (a rest-day pick, a resumed phone workout).
    var summaryTitle: String?
    /// The record card (screen 5); cleared by its own auto-dismiss or any tap.
    var recordCard: WatchRecordCard?
    /// Which exercise page is showing, so voice and rest know the on-deck context. Moving
    /// page acknowledges a rest that just ended (see `scheduleRestEndRepeat`).
    var pageIndex = 0 {
        didSet { if pageIndex != oldValue { acknowledgeRestEnd() } }
    }

    /// Left-side reps held between "Log left" and "Log right" (2G), per exercise entry.
    var pendingLeftReps: [UUID: Int] = [:]
    /// The prescribed rep floor of every AMRAP row, by set id, captured when the session is
    /// adopted — the row's own `reps` is what the lifter edits, so the target must be kept aside
    /// for "Target 5+" and "2 over target".
    var amrapTargets: [UUID: Int] = [:]

    /// `-dgWatchScreen voice`: a parsed phrase the voice sheet opens on, for screenshots.
    var debugVoiceParse: WatchVoiceParse?
    /// `-dgWatchScreen voice`: opens the voice sheet from the active page.
    var debugShowVoice = false
    /// `-dgWatchScreen settings`: Home opens on its Settings page.
    var debugOpensSettings = false
    /// `-dgWatchScreen complications[-<page>]`: every widget family at its real size, both states.
    var debugComplicationsPage: Int?
    /// `-dgWatchScreen pr`: the record card skips its 1.6 s auto-dismiss so it can be captured.
    var holdsRecordCard = false

    /// Whether `refreshHome` has run at least once this launch — the recovery path refreshes
    /// only if Home hasn't yet, so a cold launch does the store work once.
    @ObservationIgnored private(set) var hasRefreshedHome = false
    /// The 1 Hz loop (`+Tick`); nil while nothing on the session needs a tick.
    @ObservationIgnored var ticker: Task<Void, Never>?
    @ObservationIgnored var restEndRepeat: Task<Void, Never>?
    /// The rest the complication currently shows, to splice back in when the idle snapshot is
    /// rebuilt mid-workout.
    @ObservationIgnored var currentRest: WatchSnapshot.Rest?
    /// The debounced `NSPersistentStoreRemoteChange` subscription (`+Snapshot`).
    @ObservationIgnored var remoteChanges: WatchRemoteChangeObserver?

    init(
        store: WorkoutStore, preferences: WatchPreferences = .shared, runtime: WatchWorkoutRuntime? = nil,
        snapshotSuite: UserDefaults? = WatchSnapshotStore.appGroupSuite
    ) {
        self.store = store
        self.preferences = preferences
        self.runtime = runtime ?? WatchWorkoutRuntime()
        snapshots = WatchSnapshotWriter(store: store, suite: snapshotSuite) { [preferences] in
            preferences.trainingCalendar
        }
        Haptics.preferences = preferences
        WorkoutSession.defaultWarmupGrid = { [weak store] exercise in
            guard let store else { return .step(max(exercise.incrementKg, 0.5)) }
            return store.loadGrid(for: exercise, equipment: store.activeEquipment())
        }
    }

    // MARK: - Home

    /// Rebuilds Home from the store and, from the same fetches, the idle complication snapshot.
    func refreshHome(now: Date = Date()) {
        let interval = Self.signposter.beginInterval("refreshHome")
        defer { Self.signposter.endInterval("refreshHome", interval) }
        let calendar = preferences.trainingCalendar
        var state = WatchHomeState()
        state.routines = store.routines()
        state.todaysRoutine = store.todaysRoutine(calendar: calendar, now: now)
        if let routine = state.todaysRoutine {
            state.todaysLines = todaysLines(for: routine)
        }
        let dates = store.finishedWorkoutStartDates()
        state.streakWeeks = Streaks.weekly(
            workoutDates: dates, weeklyGoal: WatchPreferences.weeklyGoal, calendar: calendar, now: now
        ).current
        if let next = store.nextSession(calendar: calendar, now: now) {
            let day = next.date.formatted(.dateTime.weekday(.abbreviated))
            state.nextLabel = "\(next.routine.name) \(day)"
        }
        let unfinished = store.unfinishedWorkouts()
        state.unfinishedCount = unfinished.count
        if let unfinished = unfinished.first {
            let lastLogged = (unfinished.exercises ?? []).flatMap { $0.sets ?? [] }
                .compactMap(\.completedAt).max()
            let verdict = Self.resumeGate(
                sourceDevice: unfinished.sourceDevice, startedAt: unfinished.startedAt,
                lastLoggedAt: lastLogged, now: now
            )
            switch verdict {
            case .resumable:
                state.resumableWorkoutID = unfinished.id
                state.resumableSourceDevice = unfinished.sourceDevice
            case .liveElsewhere:
                state.inProgressElsewhereTitle = unfinished.title.isEmpty ? "Workout" : unfinished.title
            }
        }
        home = state
        hasRefreshedHome = true
        snapshots.refresh(rest: currentRest, rebuild: true, now: now, workoutDates: dates)
    }

    enum ResumeVerdict: Equatable {
        case resumable
        case liveElsewhere
    }

    /// Whether Home may offer "Resume" for an unfinished workout. The watch and the phone mirror
    /// one `WorkoutModel` through CloudKit, and `sync` on either side deletes rows the other
    /// added — so a session the phone is still logging must never be adopted here. A workout
    /// this wrist started is always its own to resume; one from another device is only offered
    /// once nothing has been logged on it for `staleAfter`, i.e. it was abandoned, not paused.
    static func resumeGate(
        sourceDevice: String, startedAt: Date, lastLoggedAt: Date?, now: Date,
        staleAfter: TimeInterval = 10 * 60
    ) -> ResumeVerdict {
        if sourceDevice == Self.sourceDevice { return .resumable }
        let lastActivity = lastLoggedAt ?? startedAt
        return now.timeIntervalSince(lastActivity) >= staleAfter ? .resumable : .liveElsewhere
    }

    /// "4×5" from the routine's planned working sets, "3×8–12" for a range, "3×0:45" for holds.
    private func todaysLines(for routine: RoutineInfo) -> [(name: String, sets: String)] {
        guard let model = store.fetchRoutineModel(id: routine.id) else {
            return routine.exercises.map { ($0.name, "") }
        }
        let slots = (model.exercises ?? []).sorted { $0.order < $1.order }
        return slots.compactMap { slot in
            guard let exercise = slot.exercise else { return nil }
            let working = (slot.plannedSets ?? []).filter { $0.setKind.countsTowardStats }
            return (exercise.name, Self.setsLine(working))
        }
    }

    static func setsLine(_ sets: [PlannedSetModel]) -> String {
        guard let first = sets.min(by: { $0.order < $1.order }) else { return "" }
        let count = sets.count
        if let seconds = first.targetSeconds, first.targetReps == nil {
            return "\(count)×\(WorkoutSession.clock(seconds))"
        }
        guard let reps = first.targetReps else { return "\(count) sets" }
        if let high = first.targetRepsHigh, high > reps { return "\(count)×\(reps)–\(high)" }
        return "\(count)×\(reps)"
    }
}
