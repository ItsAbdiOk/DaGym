import WatchKit

/// The watch's haptic vocabulary, with the phone's `Haptics` API so the shared `WorkoutSession`
/// (`completeSet`, `tickRest`, `adjustRest`…) compiles unchanged. Mapped per the spec's table
/// (`WatchHaptic`): log set → success, stepper detent → click, rest 3-2-1 → click, rest zero →
/// success, timed hold at target → directionUp, record → success twice, failed voice parse →
/// failure.
///
/// `WatchPreferences.haptics` gates the optional ones; Log set and rest-zero always fire —
/// they are confirmations you cannot see.
@MainActor
enum Haptics {
    private static var enabled: Bool { WatchPreferences.shared.haptics }

    static func warm() {}

    static func press() {}

    /// Log set. Always fires.
    static func setDone() { play(.setDone) }

    /// One click at 3, 2 and 1.
    static func restTick() { play(.restTick) }

    /// Rest zero. Always fires; repeated once after five seconds if the lifter hasn't moved on
    /// (see `WatchStore.scheduleRestEndRepeat`).
    static func restEnd() { play(.restEnd) }

    /// Two success taps, 90 ms apart.
    static func personalRecord() {
        play(.record)
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            play(.record)
        }
    }

    /// Selection click per crown detent or stepper tap.
    static func step() { play(.step) }

    static func confirm() { play(.confirm) }

    /// Failure — a voice phrase that didn't parse, or an impossible edit.
    static func invalid() { play(.voiceFailed) }

    /// A timed hold reaching its target.
    static func holdTarget() { play(.holdTarget) }

    private static func play(_ event: WatchHaptic) {
        guard let type = event.type(hapticsEnabled: enabled) else { return }
        WKInterfaceDevice.current().play(type)
    }
}

/// The spec's haptic table as data, so the mapping and the "always fires" column are testable
/// without a `WKInterfaceDevice`.
enum WatchHaptic: CaseIterable, Sendable {
    case setDone, restTick, restEnd, step, confirm, record, voiceFailed, holdTarget

    /// The `WKHapticType` this event plays.
    var wkType: WKHapticType {
        switch self {
        case .setDone, .restEnd, .record: .success
        case .restTick, .step, .confirm: .click
        case .voiceFailed: .failure
        case .holdTarget: .directionUp
        }
    }

    /// True for the confirmations that play even with haptics off: Log set, rest zero and (its
    /// cousin) the record's two taps, plus a failed voice parse — none of them can be seen.
    var alwaysFires: Bool {
        switch self {
        case .setDone, .restEnd, .record, .voiceFailed: true
        case .restTick, .step, .confirm, .holdTarget: false
        }
    }

    /// What actually plays under the Haptics setting: nil when the event is gated off.
    func type(hapticsEnabled: Bool) -> WKHapticType? {
        hapticsEnabled || alwaysFires ? wkType : nil
    }

    /// The rest countdown's haptic for a remaining second: a click at 3, 2 and 1, success at
    /// zero, nothing otherwise. What `WorkoutSession.tickRest` fires through `Haptics`.
    static func forRest(remaining: Int) -> WatchHaptic? {
        switch remaining {
        case 0: .restEnd
        case 1...3: .restTick
        default: nil
        }
    }
}
