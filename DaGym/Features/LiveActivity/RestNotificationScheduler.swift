import UserNotifications

/// The slice of `UNUserNotificationCenter` `RestNotificationScheduler` needs, so a fake can
/// assert scheduling decisions in tests without touching the real notification center. `add`
/// mirrors the center's completion-handler overload (not the `async throws` one) so a call is
/// synchronous from the caller's point of view — no `Task` needed to observe it in a test.
protocol RestNotificationCenter {
    func add(_ request: UNNotificationRequest)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: RestNotificationCenter {
    func add(_ request: UNNotificationRequest) {
        add(request, withCompletionHandler: nil)
    }
}

/// Schedules the "rest over" local notification for the moment a rest timer ends, and cancels it
/// on skip or reschedules it on +30 s. Live Activities can't play sound on their own (Apple's
/// limit), so this is what actually alerts a locked phone — the in-app bleep (`RestAlertPlayer`)
/// covers the foreground case.
@MainActor
final class RestNotificationScheduler {
    private static let identifier = "rest-timer-end"
    private let center: RestNotificationCenter

    init(center: RestNotificationCenter = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Cancels any pending alert, then schedules a new one for `endDate`. Safe to call on every
    /// rest start/adjust — cancel-then-add is exactly what a reschedule needs.
    func schedule(endDate: Date, nextSetLabel: String) {
        cancel()
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = nextSetLabel.isEmpty ? "Time for your next set." : "Next: \(nextSetLabel)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let interval = max(0.1, endDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        center.add(request)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}
