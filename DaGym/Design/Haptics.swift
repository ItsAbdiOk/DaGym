import UIKit

/// Haptic moments from the design system. One call site per moment so the
/// pattern can be tuned in one place.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// Light impact + success.
    static func setDone() {
        light.impactOccurred()
        notify.notificationOccurred(.success)
    }

    /// One of the three light taps at 3-2-1.
    static func restTick() {
        light.impactOccurred()
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
    }

    /// Rigid — swap, reorder drop.
    static func confirm() {
        rigid.impactOccurred()
    }

    /// Error — impossible plate load.
    static func invalid() {
        notify.notificationOccurred(.error)
    }
}
