import Foundation
import GymCore
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
    var resumableWorkoutID: UUID?
}

/// The watch's front door to the shared `WorkoutStore`. Everything that persists — building
/// today's session with the same prescription the phone would give, syncing every logged set,
/// finishing with PR detection and progression commit — goes through the phone's own store
/// code, compiled into this target. This type only adds what the wrist needs on top: the
/// Home state, the one-second tick, the HealthKit workout session that keeps the app alive
/// with the wrist down, the live PR preview card and the complication snapshot.
@MainActor
@Observable
final class WatchStore {
    let store: WorkoutStore
    let preferences: WatchPreferences
    let runtime: WatchWorkoutRuntime

    var home = WatchHomeState()
    var session: WorkoutSession?
    var summary: WorkoutSummary?
    /// The record card (screen 5); cleared by its own auto-dismiss or any tap.
    var recordCard: WatchRecordCard?
    /// Which exercise page is showing, so voice and rest know the on-deck context.
    var pageIndex = 0

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
    /// `-dgWatchScreen pr`: the record card skips its 1.6 s auto-dismiss so it can be captured.
    var holdsRecordCard = false

    private var ticker: Task<Void, Never>?
    private var restEndRepeat: Task<Void, Never>?

    init(store: WorkoutStore, preferences: WatchPreferences = .shared, runtime: WatchWorkoutRuntime? = nil) {
        self.store = store
        self.preferences = preferences
        self.runtime = runtime ?? WatchWorkoutRuntime()
        WorkoutSession.defaultWarmupGrid = { [weak store] exercise in
            guard let store else { return .step(max(exercise.incrementKg, 0.5)) }
            return store.loadGrid(for: exercise, equipment: store.activeEquipment())
        }
    }

    // MARK: - Home

    func refreshHome(now: Date = Date()) {
        let calendar = Calendar.current
        var state = WatchHomeState()
        state.routines = store.routines()
        state.todaysRoutine = store.todaysRoutine(calendar: calendar, now: now)
        if let routine = state.todaysRoutine {
            state.todaysLines = todaysLines(for: routine)
        }
        let dates = store.finishedWorkoutModelsNewestFirst().map(\.startedAt)
        state.streakWeeks = Streaks.weekly(
            workoutDates: dates, weeklyGoal: WatchPreferences.weeklyGoal, calendar: calendar, now: now
        ).current
        if let next = store.nextSession(calendar: calendar, now: now) {
            let day = next.date.formatted(.dateTime.weekday(.abbreviated))
            state.nextLabel = "\(next.routine.name) \(day)"
        }
        state.resumableWorkoutID = store.unfinishedWorkouts().first?.id
        home = state
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

    // MARK: - Lifecycle

    /// Starts today's routine (or `routineID`, or freestyle when nil) the way the phone does,
    /// then opens the HealthKit session that keeps the timer alive with the wrist down.
    func start(routineID: UUID?) {
        let session = routineID.map { store.startWorkout(routineIDs: [$0]) } ?? store.startFreestyle()
        // The shared start stamps "iPhone"; History groups and labels workouts by this, so a
        // wrist session says where it was logged.
        if let workoutID = session.workoutID, let model = store.workout(id: workoutID) {
            model.sourceDevice = "Apple Watch"
        }
        adopt(session)
        runtime.start(isFreestyle: routineID == nil, startedAt: session.startedAt)
    }

    func resume(workoutID: UUID) {
        guard let session = store.resumeSession(for: workoutID) else { return }
        adopt(session)
        runtime.start(isFreestyle: session.exercises.isEmpty, startedAt: session.startedAt)
    }

    private func adopt(_ session: WorkoutSession) {
        session.restHaptics = preferences.haptics
        session.onRestStateChange = { [weak self] state in self?.restStateChanged(state) }
        session.onRestTick = { [weak self] remaining in
            guard remaining == 0 else { return }
            self?.scheduleRestEndRepeat()
        }
        self.session = session
        amrapTargets = Dictionary(
            uniqueKeysWithValues: session.exercises.flatMap(\.sets)
                .filter { $0.kind == .amrap }
                .map { ($0.id, $0.reps) }
        )
        pageIndex = session.onDeckIndex ?? 0
        summary = nil
        startTicking()
    }

    /// Persists exactly what the phone persists: `finish(session:)` syncs the rows, commits
    /// progression, stamps `endedAt`, evaluates PRs against the cache and writes the snapshot.
    /// Then the HealthKit workout is saved so the rings get credit — nothing from Health goes
    /// into the store.
    func finish() {
        guard let session else { return }
        stopTicking()
        let result = store.finish(session: session, unit: preferences.weightUnit)
        preferences.lastSavedAt = Date()
        summary = result
        self.session = nil
        runtime.end(volumeKg: result.volumeKg)
        WatchSnapshotWriter.refresh(store: store, rest: nil)
    }

    func discard() {
        guard let session else { return }
        stopTicking()
        store.discard(session: session)
        self.session = nil
        runtime.discard()
        WatchSnapshotWriter.refresh(store: store, rest: nil)
    }

    func dismissSummary() {
        summary = nil
        refreshHome()
    }

    // MARK: - Tick

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let session = self.session else { return }
                session.tickRest()
                self.tickHold(session)
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
        restEndRepeat?.cancel()
    }

    private func tickHold(_ session: WorkoutSession) {
        guard let before = session.timedHold else { return }
        session.tickTimedHold()
        guard let after = session.timedHold, let target = after.targetSeconds,
              before.elapsed < target, after.elapsed >= target else { return }
        Haptics.holdTarget()
    }

    /// Rest-zero success is repeated once after five seconds if the lifter hasn't logged or
    /// moved on (the spec's "repeated once after five seconds if unacknowledged").
    private func scheduleRestEndRepeat() {
        restEndRepeat?.cancel()
        let session = self.session
        restEndRepeat = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let session, session === self.session, !session.isResting else { return }
            Haptics.restEnd()
        }
    }

    private func restStateChanged(_ state: RestState) {
        if !state.isEnded { restEndRepeat?.cancel() }
        let rest: WatchSnapshot.Rest? = state.isEnded ? nil : WatchSnapshot.Rest(
            endDate: state.endDate, totalSeconds: state.total,
            nextLabel: state.nextSetLabel(unit: preferences.weightUnit), workoutTitle: state.workoutTitle
        )
        WatchSnapshotWriter.refresh(store: store, rest: rest)
    }
}
