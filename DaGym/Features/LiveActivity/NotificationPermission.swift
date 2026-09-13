import UserNotifications

/// Requests notification permission the first time a rest timer actually starts, not at launch
/// or in onboarding — asking at the moment the feature is needed gets a much higher opt-in rate,
/// and a rest timer is the first moment DaGym has anything worth notifying about.
@MainActor
enum NotificationPermission {
    private static var didRequest = false

    static func requestIfNeeded(center: UNUserNotificationCenter = .current()) {
        guard !didRequest else { return }
        didRequest = true
        center.delegate = RestNotificationDelegate.shared
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    }
}

/// Suppresses the system banner while DaGym is in the foreground: during a workout the rest-end
/// bleep (`RestAlertPlayer`) already covers this moment, so a banner would just be noise over the
/// workout screen. Background/locked delivery (the case that actually matters) is untouched.
final class RestNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = RestNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
