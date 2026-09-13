import Foundation

/// Live work-timer state machine for `entry.isTimed` exercises: a 3-2-1
/// lead-in, then counts up (or down to the target and keeps counting),
/// pause/resume, and a stop that logs the duration and starts rest.
/// See mockup 10_01 "Timed hold · live work timer".
extension WorkoutSession {
    func startTimedHold(exerciseID: UUID, setID: UUID, targetSeconds: Int?) {
        timedHold = TimedHoldState(
            exerciseID: exerciseID, setID: setID, targetSeconds: targetSeconds,
            leadIn: 3, elapsed: 0, isPaused: false
        )
    }

    func tickTimedHold() {
        guard var hold = timedHold, !hold.isPaused else { return }
        if hold.leadIn > 0 {
            hold.leadIn -= 1
            Haptics.restTick()
        } else {
            hold.elapsed += 1
        }
        timedHold = hold
    }

    func pauseResumeTimedHold() {
        timedHold?.isPaused.toggle()
        Haptics.step()
    }

    /// Stops the live hold, logging its elapsed duration on the current set
    /// and completing it (which starts the rest timer). Returns nil when
    /// stopped during the lead-in, since nothing was logged.
    @discardableResult
    func stopTimedHold() -> Int? {
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
        Haptics.setDone()
        startRest(seconds: exercises[ei].exercise.restSeconds, after: ei, set: si)
    }
}
