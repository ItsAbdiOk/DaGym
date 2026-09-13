import UserNotifications

/// Requests notification permission the first time a rest timer actually starts, not at launch
/// or in onboarding — asking at the moment the feature is needed gets a much higher opt-in rate,
/// and a rest timer is the first moment DaGym has anything worth notifying about.
@MainActor
enum NotificationPermission {
    private static var request: Task<Void, Never>?

    static func requestIfNeeded(center: UNUserNotificationCenter = .current()) {
        guard request == nil else { return }
        center.delegate = RestNotificationDelegate.shared
        request = Task { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    }

    /// Requests if needed, then waits for the system prompt to resolve — so the very first rest's
    /// "Rest over" alert is scheduled after the user has answered, not before.
    static func awaitRequest(center: UNUserNotificationCenter = .current()) async {
        requestIfNeeded(center: center)
        await request?.value
    }
}

/// The permission gate `RestActivityController` waits on before scheduling; a protocol so tests
/// can resolve it instantly without touching the real, prompt-showing notification center.
protocol RestNotificationAuthorizing: Sendable {
    func awaitAuthorization() async
}

struct SystemNotificationAuthorizer: RestNotificationAuthorizing {
    func awaitAuthorization() async { await NotificationPermission.awaitRequest() }
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
