import UIKit

/// Haptic moments from the design system. One call site per moment so the
/// pattern can be tuned in one place.
///
/// Generators are kept alive as statics and re-armed with `prepare()` whenever a touch
/// begins: the Taptic Engine takes tens of milliseconds to spin up from cold, and an
/// un-prepared generator either fires late or drops the first tap of a session entirely,
/// which is what "the buttons don't feel responsive" actually is on device.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// Arm every generator. Cheap, idempotent, and only holds the engine warm for a
    /// second or two — call it when a touch goes down, and when a screen that is about
    /// to take taps appears.
    static func warm() {
        light.prepare()
        rigid.prepare()
        soft.prepare()
        notify.prepare()
        selection.prepare()
    }

    /// Touch-down on any control. Soft and quiet: this fires on every press in the app,
    /// so it has to sit under the moment that follows rather than compete with it.
    static func press() {
        soft.impactOccurred(intensity: 0.6)
        soft.prepare()
    }

    /// Light impact + success.
    static func setDone() {
        light.impactOccurred()
        notify.notificationOccurred(.success)
        notify.prepare()
    }

    /// One of the three light taps at 3-2-1.
    static func restTick() {
        light.impactOccurred()
        light.prepare()
    }

    /// Success (sound and flash handled by the caller).
    static func restEnd() {
        notify.notificationOccurred(.success)
    }

    /// Double success, 90 ms apart.
    static func personalRecord() {
        notify.notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            notify.notificationOccurred(.success)
        }
    }

    /// Selection click per increment.
    static func step() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// Rigid — swap, reorder drop.
    static func confirm() {
        rigid.impactOccurred()
        rigid.prepare()
    }

    /// Error — impossible plate load.
    static func invalid() {
        notify.notificationOccurred(.error)
    }
}
