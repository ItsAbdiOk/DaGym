import UserNotifications

/// Requests notification permission the first time a rest timer actually starts, not at launch
/// or in onboarding — asking at the moment the feature is needed gets a much higher opt-in rate,
/// and a rest timer is the first moment DaGym has anything worth notifying about.
@MainActor
enum NotificationPermission {
    private static var request: Task<Void, Never>?

    /// The delegate is *not* set here any more — `DaGymAppDelegate` does it once per launch. A
    /// user who granted permission long ago never reaches this function, and used to get the
    /// system banner over their own workout screen because nothing had installed the delegate.
    static func requestIfNeeded(center: UNUserNotificationCenter = .current()) {
        guard request == nil else { return }
        request = Task { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    }

    /// Requests if needed, then waits for the system prompt to resolve — so the very first rest's
    /// "Rest over" alert is scheduled after the user has answered, not before.
    static func awaitRequest(center: UNUserNotificationCenter = .current()) async {
        requestIfNeeded(center: center)
        await request?.value
    }
}

/// Asking for, and reading back, notification permission — as a protocol so Settings can be
/// tested against a granted, denied or not-yet-asked system without a device prompt.
protocol NotificationAuthorizing: Sendable {
    /// What iOS currently thinks, including a "denied" the user set in iOS Settings after
    /// granting once.
    func status() async -> UNAuthorizationStatus
    /// Prompts if it has never been asked, then reports where that left things. A no-op prompt
    /// (already determined) still returns the real status.
    func request() async -> UNAuthorizationStatus
}

struct SystemNotificationAuthorization: NotificationAuthorizing {
    func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func request() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        return await center.notificationSettings().authorizationStatus
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
