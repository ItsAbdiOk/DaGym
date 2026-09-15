import Foundation
import GymCore

/// The record card (spec 5): shown for 1.6 s after a set beats the cached best e1RM for its
/// exercise. A *preview* only — the PR cache itself is written at finish by the shared
/// `WorkoutStore.evaluatePRs`, exactly as on the phone, so the two devices can never disagree
/// about who holds a record.
struct WatchRecordCard: Identifiable {
    let id = UUID()
    var exerciseName: String
    var weightKg: Double
    var reps: Int
    var previousE1RM: Double?
    var newE1RM: Double
}

extension WatchStore {
    /// Today's on-deck values for a page, as the steppers edit them. Edits go straight onto the
    /// session's `SetEntry` so "Fix" after voice and a crown turn are the same write.
    func currentSetIndex(in entry: WorkoutExerciseEntry) -> Int? {
        entry.sets.firstIndex { !$0.isDone }
    }

    func updateSet(exerciseID: UUID, _ change: (inout SetEntry) -> Void) {
        guard let session,
              let ei = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = currentSetIndex(in: session.exercises[ei]) else { return }
        change(&session.exercises[ei].sets[si])
    }

    /// Log set / Log warm-up. Warm-ups take the spec's 60 s rest and skip the PR preview.
    func logCurrentSet(exerciseID: UUID, effort: Effort? = nil) {
        guard let session,
              let ei = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = currentSetIndex(in: session.exercises[ei]) else { return }
        let entry = session.exercises[ei]
        let set = entry.sets[si]
        acknowledgeRestEnd()
        session.completeSet(exerciseID: exerciseID, setID: set.id, effort: effort)
        if set.kind == .warmup, session.isResting, session.restRemaining > 60 {
            session.adjustRest(by: 60 - session.restRemaining)
            session.restTotal = 60
        }
        store.sync(session: session)
        if set.kind.countsTowardStats { checkRecord(entry: entry, set: session.exercises[ei].sets[si]) }
        if session.exercises[ei].isComplete { advancePage(after: ei) }
    }

    /// Per side (2G): the left count is held until the right is logged, then both go onto the
    /// one row as a total — the convention the phone and the progression engine share.
    func logLeftSide(exerciseID: UUID, reps: Int) {
        pendingLeftReps[exerciseID] = reps
        Haptics.step()
    }

    func logRightSide(exerciseID: UUID, reps: Int, effort: Effort? = nil) {
        let left = pendingLeftReps.removeValue(forKey: exerciseID) ?? reps
        updateSet(exerciseID: exerciseID) { $0.reps = left + reps }
        logCurrentSet(exerciseID: exerciseID, effort: effort)
    }

    func hasLoggedLeft(exerciseID: UUID) -> Bool { pendingLeftReps[exerciseID] != nil }

    // MARK: - Timed hold / cardio

    func startHold(exerciseID: UUID) {
        guard let session,
              let entry = session.exercises.first(where: { $0.id == exerciseID }),
              let si = currentSetIndex(in: entry) else { return }
        let set = entry.sets[si]
        session.startTimedHold(exerciseID: exerciseID, setID: set.id, targetSeconds: set.cardioSeconds)
    }

    /// Stop & log: the real time held (or run) goes on the row; a stop inside the 3-2-1 lead-in
    /// logs nothing. Cardio rows keep whatever distance the stepper set.
    func stopHold(exerciseID: UUID) {
        guard let session else { return }
        guard session.stopTimedHold() != nil else { return }
        acknowledgeRestEnd()
        store.sync(session: session)
        if let ei = session.exercises.firstIndex(where: { $0.id == exerciseID }),
           session.exercises[ei].isComplete { advancePage(after: ei) }
    }

    // MARK: - Rest

    func addRest(seconds: Int) { session?.adjustRest(by: seconds) }
    func skipRest() { session?.skipRest() }

    /// Crown scrub on the full-screen rest: sets the remaining time outright, in 15 s detents.
    func scrubRest(to remaining: Int) {
        guard let session else { return }
        let clamped = max(0, remaining)
        session.adjustRest(by: clamped - session.restRemaining)
    }

    // MARK: - Records

    private func checkRecord(entry: WorkoutExerciseEntry, set: SetEntry) {
        guard let session, let load = previewLoadKg(entry: entry, set: set, asOf: session.startedAt),
              OneRepMax.isEligible(weight: load, reps: set.reps),
              let e1rm = OneRepMax.estimate(weight: load, reps: set.reps) else { return }
        let best = entry.exercise.bestE1RM ?? 0
        guard e1rm > best + 0.05 else { return }
        recordCard = WatchRecordCard(
            exerciseName: entry.exercise.name, weightKg: set.weightKg, reps: set.reps,
            previousE1RM: entry.exercise.bestE1RM, newE1RM: e1rm
        )
        Haptics.personalRecord()
        // The next set of this exercise compares against the new best, as the phone's cache
        // would after finish.
        if let ei = session.exercises.firstIndex(where: { $0.id == entry.id }) {
            session.exercises[ei].exercise.bestE1RM = e1rm
        }
    }

    /// The load the preview estimates from — the same number `WorkoutStore.evaluatePRs` will use
    /// at finish (`PerformedSet.effectiveWeightKg`): the bar weight for a weight × reps lift,
    /// bodyweight plus the added load for a weighted dip or pull-up. Comparing the added load
    /// alone against a cache that holds the total either never fires or fires on every set.
    /// Nil for the styles that have no e1RM preview.
    func previewLoadKg(entry: WorkoutExerciseEntry, set: SetEntry, asOf: Date) -> Double? {
        switch entry.exercise.loggingStyle {
        case .weightReps:
            return set.weightKg
        case .weightedBodyweight:
            let bodyweight = store.latestBodyMeasurement(asOf: asOf)?.bodyweightKg
            return PerformedSet(
                kind: set.kind, weightKg: set.weightKg, reps: set.reps, bodyweightKg: bodyweight, date: asOf
            ).effectiveWeightKg
        default:
            return nil
        }
    }

    private func advancePage(after index: Int) {
        guard let session, let next = session.onDeckIndex, next != index else { return }
        pageIndex = next
    }
}
