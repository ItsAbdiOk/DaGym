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

    @Test("rest remaining maps to click at 3, 2, 1, success at 0, nothing otherwise")
    func restCountdown() {
        #expect(WatchHaptic.forRest(remaining: 3) == .restTick)
        #expect(WatchHaptic.forRest(remaining: 2) == .restTick)
        #expect(WatchHaptic.forRest(remaining: 1) == .restTick)
        #expect(WatchHaptic.forRest(remaining: 0) == .restEnd)
        #expect(WatchHaptic.forRest(remaining: 4) == nil)
        #expect(WatchHaptic.forRest(remaining: 30) == nil)
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
