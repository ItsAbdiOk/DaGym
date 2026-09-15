import Foundation
import GymCore
import HealthKit
import SwiftUI

extension WatchStore {
    /// Starts today's routine (or `routineID`, or freestyle when nil) the way the phone does,
    /// then opens the HealthKit session that keeps the timer alive with the wrist down.
    func start(routineID: UUID?) {
        let session = routineID.map { store.startWorkout(routineIDs: [$0]) } ?? store.startFreestyle()
        // The shared start stamps "iPhone"; History groups and labels workouts by this, so a
        // wrist session says where it was logged.
        if let workoutID = session.workoutID, let model = store.workout(id: workoutID) {
            model.sourceDevice = Self.sourceDevice
        }
        adopt(session)
        runtime.start(isFreestyle: routineID == nil, startedAt: session.startedAt)
    }

    func resume(workoutID: UUID) {
        guard let session = store.resumeSession(for: workoutID) else { return }
        adopt(session)
        runtime.start(isFreestyle: session.exercises.isEmpty, startedAt: session.startedAt, resuming: true)
    }

    /// After a kill mid-workout (see `WatchAppDelegate`): the HealthKit session watchOS kept
    /// alive is handed to the runtime when there is a *wrist* workout to resume into, and
    /// ended when there isn't — a finished or discarded workout has nothing to run for, and
    /// a stale phone workout Home happens to offer was never this session's.
    func adoptRecoveredRuntime(_ hkSession: HKWorkoutSession) {
        if !hasRefreshedHome { refreshHome() }
        runtime.adopt(recovered: hkSession, keep: Self.shouldKeepRecoveredSession(home: home))
    }

    static func shouldKeepRecoveredSession(home: WatchHomeState) -> Bool {
        home.resumableWorkoutID != nil && home.resumableSourceDevice == sourceDevice
    }

    /// Takes a built session live: callbacks, AMRAP targets, the on-deck page, the ticker.
    func adopt(_ session: WorkoutSession) {
        // Always on: the session's flag would silence rest-zero too, and the spec keeps that
        // one (with Log set) firing under Haptics off. The watch `Haptics` gates the 3-2-1
        // clicks itself (`WatchHaptic.alwaysFires`).
        session.restHaptics = true
        session.onRestStateChange = { [weak self] state in self?.restStateChanged(state) }
        session.onRestTick = { [weak self] remaining in
            if let announcement = WatchAccessibility.restAnnouncement(remaining: remaining) {
                AccessibilityNotification.Announcement(announcement).post()
            }
            guard remaining == 0 else { return }
            self?.scheduleRestEndRepeat()
        }
        self.session = session
        // A CloudKit merge can hand a resumed workout two rows with one id; the first wins
        // rather than trapping at launch.
        amrapTargets = Dictionary(
            session.exercises.flatMap(\.sets).filter { $0.kind == .amrap }.map { ($0.id, $0.reps) },
            uniquingKeysWith: { first, _ in first }
        )
        pageIndex = session.onDeckIndex ?? 0
        summary = nil
        summaryTitle = nil
        // A resumed session may come back mid-rest or mid-hold; a fresh one has nothing to
        // tick until its first set is logged.
        ensureTicking()
        // The summary's body map parses the vendored SVG paths on first use; done here, off
        // the main actor, so the first Summary after Finish doesn't stall on it.
        WatchBodyRegions.warm()
    }

    /// Persists exactly what the phone persists: `finish(session:)` syncs the rows, commits
    /// progression, stamps `endedAt`, evaluates PRs against the cache and writes the snapshot
    /// (`WidgetSnapshotWriter.refresh(store:)`, from inside the store). Then the HealthKit
    /// workout is saved so the rings get credit — nothing from Health goes into the store.
    func finish() {
        guard let session else { return }
        stopTicking()
        currentRest = nil
        let result = store.finish(
            session: session, weeklyGoal: WatchPreferences.weeklyGoal,
            calendar: preferences.trainingCalendar, unit: preferences.weightUnit
        )
        preferences.lastSavedAt = Date()
        summaryTitle = session.title
        summary = result
        self.session = nil
        runtime.end()
    }

    func discard() {
        guard let session else { return }
        stopTicking()
        currentRest = nil
        store.discard(session: session)
        self.session = nil
        runtime.discard()
        snapshots.refresh(rest: nil)
    }

    func dismissSummary() {
        summary = nil
        summaryTitle = nil
        refreshHome()
    }
}
