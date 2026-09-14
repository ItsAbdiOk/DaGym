import Foundation

/// Live work-timer state machine for `entry.isTimed` exercises: a 3-2-1
/// lead-in, then counts up (or down to the target and keeps counting),
/// pause/resume, and a stop that logs the duration and starts rest.
/// Everything is derived from `startedAt` and the pause dates against
/// `now()`, so a plank keeps counting while the phone is locked.
/// See mockup 10_01 "Timed hold · live work timer".
extension WorkoutSession {
    static let holdLeadInSeconds = 3

    func startTimedHold(exerciseID: UUID, setID: UUID, targetSeconds: Int?) {
        timedHold = TimedHoldState(
            exerciseID: exerciseID, setID: setID, targetSeconds: targetSeconds,
            startedAt: now(), leadIn: Self.holdLeadInSeconds, elapsed: 0
        )
    }

    /// Refreshes the hold's `leadIn`/`elapsed` cache from the clock. A lead-in tap fires once per
    /// lead-in second actually crossed, never for the seconds a suspension skipped over.
    func tickTimedHold() {
        guard var hold = timedHold, !hold.isPaused else { return }
        let active = Self.activeSeconds(of: hold, now: now())
        let leadIn = max(0, Self.holdLeadInSeconds - active)
        let elapsed = max(0, active - Self.holdLeadInSeconds)
        guard leadIn != hold.leadIn || elapsed != hold.elapsed else { return }
        if leadIn < hold.leadIn, leadIn > 0 { Haptics.restTick() }
        hold.leadIn = leadIn
        hold.elapsed = elapsed
        timedHold = hold
    }

    /// Whole seconds the hold has been running, excluding time spent paused.
    static func activeSeconds(of hold: TimedHoldState, now: Date) -> Int {
        let end = hold.pausedAt ?? now
        let interval = end.timeIntervalSince(hold.startedAt) - hold.pausedInterval
        return max(0, Int(interval))
    }

    func pauseResumeTimedHold() {
        guard var hold = timedHold else { return }
        let current = now()
        if let pausedAt = hold.pausedAt {
            hold.pausedInterval += current.timeIntervalSince(pausedAt)
            hold.pausedAt = nil
        } else {
            hold.pausedAt = current
        }
        timedHold = hold
        Haptics.step()
    }

    /// Stops the live hold, logging its elapsed duration on the current set
    /// and completing it (which starts the rest timer). Returns nil when
    /// stopped during the lead-in, since nothing was logged.
    @discardableResult
    func stopTimedHold() -> Int? {
        tickTimedHold()
        guard let hold = timedHold, hold.leadIn == 0 else {
            timedHold = nil
            return nil
        }
        completeTimedSet(exerciseID: hold.exerciseID, setID: hold.setID, durationSeconds: hold.elapsed)
        timedHold = nil
        return hold.elapsed
    }

    private func completeTimedSet(exerciseID: UUID, setID: UUID, durationSeconds: Int) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].durationSeconds = durationSeconds
        exercises[ei].sets[si].isDone = true
        if exercises[ei].isCardio { exercises[ei].sets[si].adoptCardioTargets() }
        Haptics.setDone()
        startRest(seconds: restSeconds(after: ei, set: si), after: ei, set: si)
    }
}
