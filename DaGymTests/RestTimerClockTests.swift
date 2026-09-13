import Foundation
import GymCore
import Testing

@testable import DaGym

/// A clock the test moves by hand, so a "locked the phone for two minutes" gap is one line.
@MainActor
private final class ManualClock {
    var date: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.date = date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
@Suite("Rest and hold timers follow the wall clock")
struct RestTimerClockTests {
    private func makeSession(clock: ManualClock, restSeconds: Int = 150) -> WorkoutSession {
        let exercise = ExerciseInfo(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", restSeconds: restSeconds
        )
        let sets = [
            SetEntry(kind: .working, weightKg: 80, reps: 8),
            SetEntry(kind: .working, weightKg: 80, reps: 8)
        ]
        let entry = WorkoutExerciseEntry(exercise: exercise, sets: sets)
        let session = WorkoutSession(title: "Push", subtitle: "", startedAt: clock.date, exercises: [entry])
        session.now = { clock.date }
        return session
    }

    @Test("a 120 s clock jump drops restRemaining by 120 on the next tick")
    func clockJumpDropsRemaining() {
        let clock = ManualClock()
        let session = makeSession(clock: clock)
        session.startRest(seconds: 150, after: 0, set: 0)
        #expect(session.restRemaining == 150)

        clock.advance(1)
        session.tickRest()
        #expect(session.restRemaining == 149)

        clock.advance(120)
        session.tickRest()
        #expect(session.restRemaining == 29)
    }

    @Test("a jump past the end lands on zero once and reports a natural end")
    func clockJumpPastEndEndsOnce() {
        let clock = ManualClock()
        let session = makeSession(clock: clock)
        var states: [RestState] = []
        session.onRestStateChange = { states.append($0) }
        var ticks: [Int] = []
        session.onRestTick = { ticks.append($0) }
        session.startRest(seconds: 60, after: 0, set: 0)

        clock.advance(300)
        session.tickRest()
        session.tickRest()

        #expect(session.restRemaining == 0)
        #expect(!session.isResting)
        #expect(ticks == [0])
        #expect(states.map(\.isEnded) == [false, true])
        #expect(states.last?.isSkipped == false)
    }

    @Test("the rest state carries the wall-clock end date the Live Activity counts to")
    func restStateCarriesEndDate() {
        let clock = ManualClock()
        let session = makeSession(clock: clock)
        var states: [RestState] = []
        session.onRestStateChange = { states.append($0) }

        session.startRest(seconds: 90, after: 0, set: 0)

        #expect(states.first?.endDate == clock.date.addingTimeInterval(90))
        #expect(session.restEndDate == clock.date.addingTimeInterval(90))
    }

    @Test("+30 s extends from the clock's real remaining, not a stale counter")
    func adjustRestUsesClock() {
        let clock = ManualClock()
        let session = makeSession(clock: clock)
        session.startRest(seconds: 100, after: 0, set: 0)

        clock.advance(70)
        session.adjustRest(by: 30)

        #expect(session.restRemaining == 60)
        #expect(session.restEndDate == clock.date.addingTimeInterval(60))
    }

    @Test("skip clears the end date so a later tick can't resurrect the rest")
    func skipClearsEndDate() {
        let clock = ManualClock()
        let session = makeSession(clock: clock)
        session.startRest(seconds: 100, after: 0, set: 0)

        session.skipRest()
        clock.advance(1)
        session.tickRest()

        #expect(session.restEndDate == nil)
        #expect(session.restRemaining == 0)
    }

    @Test("a hold's elapsed time is measured from holdStartedAt, through a suspension")
    func holdElapsedFromStartDate() {
        let clock = ManualClock()
        let session = makeSession(clock: clock)
        let entry = session.exercises[0]
        session.startTimedHold(exerciseID: entry.id, setID: entry.sets[0].id, targetSeconds: 60)
        #expect(session.timedHold?.startedAt == clock.date)
        #expect(session.timedHold?.leadIn == 3)

        clock.advance(2)
        session.tickTimedHold()
        #expect(session.timedHold?.leadIn == 1)
        #expect(session.timedHold?.elapsed == 0)

        clock.advance(48)
        session.tickTimedHold()
        #expect(session.timedHold?.leadIn == 0)
        #expect(session.timedHold?.elapsed == 47)
    }

    @Test("paused time is excluded from a hold's elapsed")
    func holdPauseExcludesPausedTime() {
        let clock = ManualClock()
        let session = makeSession(clock: clock)
        let entry = session.exercises[0]
        session.startTimedHold(exerciseID: entry.id, setID: entry.sets[0].id, targetSeconds: nil)

        clock.advance(13)
        session.pauseResumeTimedHold()
        #expect(session.timedHold?.isPaused == true)
        clock.advance(60)
        session.tickTimedHold()
        #expect(session.timedHold?.elapsed == 0)
        session.pauseResumeTimedHold()
        clock.advance(5)
        session.tickTimedHold()

        #expect(session.timedHold?.isPaused == false)
        #expect(session.timedHold?.elapsed == 15)
    }

    @Test("stop logs the clock-derived duration even without an intervening tick")
    func stopLogsDuration() {
        let clock = ManualClock()
        let session = makeSession(clock: clock, restSeconds: 60)
        let entry = session.exercises[0]
        session.startTimedHold(exerciseID: entry.id, setID: entry.sets[0].id, targetSeconds: 60)

        clock.advance(3 + 42)
        let logged = session.stopTimedHold()

        #expect(logged == 42)
        #expect(session.exercises[0].sets[0].durationSeconds == 42)
        #expect(session.exercises[0].sets[0].isDone)
        #expect(session.timedHold == nil)
        #expect(session.restRemaining == 60)
    }

    @Test("editing effort on a done set does not restart rest")
    func effortEditKeepsRest() {
        let clock = ManualClock()
        let session = makeSession(clock: clock)
        let entry = session.exercises[0]
        session.completeSet(exerciseID: entry.id, setID: entry.sets[0].id, effort: Effort(rpe: 8))
        clock.advance(100)
        session.tickRest()
        #expect(session.restRemaining == 50)

        session.setEffort(exerciseID: entry.id, setID: entry.sets[0].id, effort: Effort(rpe: 9))

        #expect(session.restRemaining == 50)
        #expect(session.exercises[0].sets[0].effort == Effort(rpe: 9))
        #expect(session.exercises[0].sets[0].isDone)
    }
}
