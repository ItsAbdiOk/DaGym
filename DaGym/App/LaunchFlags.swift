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
    static var isUnitTestHost: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }

    /// Either kind of test process.
    static var isTesting: Bool { isUITesting || isUnitTestHost }
}
