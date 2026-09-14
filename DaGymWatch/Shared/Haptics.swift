import WatchKit

/// The watch's haptic vocabulary, with the phone's `Haptics` API so the shared `WorkoutSession`
/// (`completeSet`, `tickRest`, `adjustRest`…) compiles unchanged. Mapped per the spec's table:
/// log set → success, stepper detent → click, rest 3-2-1 → click, rest zero → success, timed
/// hold at target → directionUp, record → success twice, failed voice parse → failure.
///
/// `WatchPreferences.haptics` gates the optional ones; Log set and rest-zero always fire —
/// they are confirmations you cannot see.
@MainActor
enum Haptics {
    private static var enabled: Bool { WatchPreferences.shared.haptics }

    static func warm() {}

    static func press() {}

    /// Log set. Always fires.
    static func setDone() { WKInterfaceDevice.current().play(.success) }

    /// One click at 3, 2 and 1.
    static func restTick() {
        guard enabled else { return }
        WKInterfaceDevice.current().play(.click)
    }

    /// Rest zero. Always fires; repeated once after five seconds if the lifter hasn't moved on
    /// (see `WatchStore.scheduleRestEndRepeat`).
    static func restEnd() { WKInterfaceDevice.current().play(.success) }

    /// Two success taps, 90 ms apart.
    static func personalRecord() {
        WKInterfaceDevice.current().play(.success)
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            WKInterfaceDevice.current().play(.success)
        }
    }

    /// Selection click per crown detent or stepper tap.
    static func step() {
        guard enabled else { return }
        WKInterfaceDevice.current().play(.click)
    }

    static func confirm() {
        guard enabled else { return }
        WKInterfaceDevice.current().play(.click)
    }

    /// Failure — a voice phrase that didn't parse, or an impossible edit.
    static func invalid() { WKInterfaceDevice.current().play(.failure) }

    /// A timed hold reaching its target.
    static func holdTarget() {
        guard enabled else { return }
        WKInterfaceDevice.current().play(.directionUp)
    }
}
