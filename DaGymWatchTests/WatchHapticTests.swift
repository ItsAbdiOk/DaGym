import Foundation
import GymCore
import Testing
import WatchKit

@testable import DaGymWatch

/// The spec's haptics table: "Log set fires success. Stepper detents click. Rest fires a click at
/// 3, 2 and 1 and a success at zero … A timed hold reaching target fires directionUp. A record
/// fires success twice. A failed voice parse fires failure. With haptics off, Log set and
/// rest-zero still fire."
@Suite("Watch haptic mapping")
struct WatchHapticTests {
    @Test("each event plays the spec's WKHapticType")
    func mapping() {
        #expect(WatchHaptic.setDone.wkType == .success)
        #expect(WatchHaptic.step.wkType == .click)
        #expect(WatchHaptic.restTick.wkType == .click)
        #expect(WatchHaptic.restEnd.wkType == .success)
        #expect(WatchHaptic.holdTarget.wkType == .directionUp)
        #expect(WatchHaptic.record.wkType == .success)
        #expect(WatchHaptic.voiceFailed.wkType == .failure)
    }

    /// Drives the real path — `WorkoutSession.tickRest` calling `Haptics` — rather than a
    /// lookup table nothing calls: a 5 s rest ticked second by second clicks at 3, 2 and 1 and
    /// fires success at zero, and nothing before that.
    @Test("the rest countdown clicks at 3, 2, 1 and fires success at 0 through tickRest")
    @MainActor
    func restCountdown() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = start
        let bench = ExerciseInfo(
            name: "Bench", primary: [.chest], equipment: "barbell", loggingStyle: .weightReps
        )
        let entry = WorkoutExerciseEntry(exercise: bench, sets: [SetEntry(weightKg: 60, reps: 5)])
        let session = WorkoutSession(title: "t", subtitle: "", startedAt: start, exercises: [entry])
        session.now = { clock }
        session.restHaptics = true
        session.startRest(seconds: 5, after: 0, set: 0)
        Haptics.recorded = []

        for second in 1...5 {
            clock = start.addingTimeInterval(Double(second))
            session.tickRest()
        }

        #expect(Haptics.recorded == [.restTick, .restTick, .restTick, .restEnd])
    }

    @Test("with haptics off only the unseen confirmations still play")
    func hapticsOff() {
        #expect(WatchHaptic.setDone.type(hapticsEnabled: false) == .success)
        #expect(WatchHaptic.restEnd.type(hapticsEnabled: false) == .success)
        #expect(WatchHaptic.restTick.type(hapticsEnabled: false) == nil)
        #expect(WatchHaptic.step.type(hapticsEnabled: false) == nil)
        #expect(WatchHaptic.holdTarget.type(hapticsEnabled: false) == nil)
        for event in WatchHaptic.allCases {
            #expect(event.type(hapticsEnabled: true) == event.wkType)
        }
    }
}
