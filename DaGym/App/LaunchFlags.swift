import Foundation

/// Launch-argument flags read once at process start. `-dgUITest` is used
/// only by `DaGymUITests`: it swaps in a fresh in-memory store (seeded like
/// any other launch) and disables animations so XCUITest assertions don't
/// race Core Animation. Debug-only — the UI-test bundle always runs
/// against the Debug build, so there is no Release path to gate.
enum LaunchFlags {
    /// Whether this process was launched with `-dgUITest`.
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-dgUITest")
        #else
        false
        #endif
    }

    /// True when the process is the host for a unit-test bundle (XCTest / Swift Testing set
    /// `XCTestConfigurationFilePath` or `XCTestBundlePath`). The app then skips CloudKit, the
    /// App Group store and HealthKit so the host launches instantly and tests build their own
    /// in-memory containers.
    /// The `-dgTestHost` arm is `#if DEBUG` like every other launch-argument flag here. In a
    /// Release build it made the container in-memory, skipped seeding and the app delegate and
    /// returned nil from every intent — a data-loss switch anyone could flip on a shipped
    /// binary. The XCTest environment/class sniffing below needs no gate: neither can be true
    /// in an App Store process.
    static var isUnitTestHost: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dgTestHost") { return true }
        #endif
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil {
            return true
        }
        // The XCTest framework is only ever loaded into a test host.
        return NSClassFromString("XCTestCase") != nil
    }

    /// Whether this process was launched with `-dgScreenshots`: the App Store screenshot
    /// build. Like `-dgUITest` it runs on a throwaway in-memory store with animations off, but
    /// the store is filled by `ScreenshotMode` (eight weeks of history, a workout mid-set, a
    /// bodyweight series, milestones, a schedule) so every marketing shot has real-looking
    /// data. `-dgScreenshotScreen <name>` opens one screen directly — see `ScreenshotScreen`.
    static var isScreenshotting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-dgScreenshots")
        #else
        false
        #endif
    }

    /// Either kind of test process, or the screenshot build — every side-effecting service
    /// (notifications, calendar sync, widgets, HealthKit, CloudKit) stays inert for all three.
    static var isTesting: Bool { isUITesting || isUnitTestHost || isScreenshotting }

    /// Whether this process was launched with `-dgOnboarding`. Paired with `-dgUITest`, this
    /// resets `Preferences.hasCompletedOnboarding` to `false` so `testOnboardingCompletes` always
    /// starts from a fresh onboarding flow regardless of what a previous simulator run left in
    /// `UserDefaults.standard`. Without it, `-dgUITest` alone marks onboarding complete so the
    /// existing smoke tests land straight on the tab bar.
    static var forcesOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-dgOnboarding")
        #else
        false
        #endif
    }
}
