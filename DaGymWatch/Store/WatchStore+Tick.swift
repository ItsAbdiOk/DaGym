import Foundation
import GymCore

extension WatchStore {
    // MARK: - Tick

    /// True while the session has something a 1 Hz tick moves: a rest counting down or a
    /// timed hold running. Nothing else on the page changes by the second.
    var needsTicker: Bool {
        guard let session else { return false }
        return session.isResting || session.timedHold != nil
    }

    var isTicking: Bool {
        guard let ticker else { return false }
        return !ticker.isCancelled
    }

    /// Starts the loop if `needsTicker` and it isn't already running. The loop ends itself
    /// once neither a rest nor a hold is live — with the HealthKit session keeping the app
    /// alive, a tick for the whole workout was a wake-up per second wrist-down for an hour
    /// with nothing to do between sets. `tickRest` re-derives from `restEndDate`, so the
    /// timer's accuracy doesn't depend on the loop running continuously.
    func ensureTicking() {
        guard needsTicker, !isTicking else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                // A cancelled loop must not clear a ticker that has since been replaced.
                guard !Task.isCancelled, let self else { return }
                guard let session = self.session, self.needsTicker else {
                    self.ticker = nil
                    return
                }
                session.tickRest()
                self.tickHold(session)
            }
        }
    }

    func stopTicking() {
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

    // MARK: - Rest

    /// Rest-zero success is repeated once after five seconds if the lifter hasn't logged or
    /// moved on (the spec's "repeated once after five seconds if unacknowledged").
    func scheduleRestEndRepeat() {
        restEndRepeat?.cancel()
        let session = self.session
        restEndRepeat = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let session, session === self.session, !session.isResting else { return }
            Haptics.restEnd()
        }
    }

    /// True while the five-second repeat is still armed.
    var isRestEndRepeatPending: Bool {
        guard let restEndRepeat else { return false }
        return !restEndRepeat.isCancelled
    }

    /// Anything that shows the lifter has moved on — a set logged, a hold stopped, a page
    /// swiped — cancels the repeat: the spec repeats it "if unacknowledged", and starting a new
    /// rest is not the only acknowledgement.
    func acknowledgeRestEnd() {
        restEndRepeat?.cancel()
    }

    /// Every rest change — start, `+30s`, a crown scrub, skip, end — reaches the complication
    /// by splicing the rest into the cached idle snapshot; the store is not touched.
    func restStateChanged(_ state: RestState) {
        if !state.isEnded { restEndRepeat?.cancel() }
        let rest: WatchSnapshot.Rest? = state.isEnded ? nil : WatchSnapshot.Rest(
            endDate: state.endDate, totalSeconds: state.total,
            nextLabel: state.nextSetLabel(unit: preferences.weightUnit), workoutTitle: state.workoutTitle
        )
        currentRest = rest
        snapshots.refresh(rest: rest)
        ensureTicking()
    }
}
