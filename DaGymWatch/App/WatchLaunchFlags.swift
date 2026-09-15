import Foundation

/// Debug-only launch arguments for driving the watch simulator (there is no CloudKit account
/// there, so the real store is empty).
///
/// - `-dgWatchSample`: an in-memory store seeded with a Push A routine (every set shape), Pull A
///   and Legs, a schedule that puts Push A on today, and two finished sessions so prescriptions
///   and ghosts have a baseline. See `WatchSampleSeeder`.
/// - `-dgWatchScreen <name>`: opens a screen state directly. Names: `home` (1A), `home-rest` (1B), `active`
///   (the workout started on Bench Press, first warm-up), `working` (2A), `amrap` (2C),
///   `active-<n>` (page n: 3 pull-up 2D, 4 assisted dip 2E, 5 plank 2F, 6 split squat 2G, 7 cardio),
///   `rest` (3A inline after logging bench set 1), `rest-full` (3B), `rest-final` (3C), `voice`
///   (4B with a parsed phrase), `pr` (5), `summary` (6), `settings` (8), `complications` (7 and
///   3D: every widget family at its real size, idle and resting).
/// - `-dgWatchAlwaysOn`: forces the always-on (reduced luminance) layouts.
/// - `-dgWatchTextSize`: renders at the largest accessibility text size (`.accessibility5`),
///   since neither `-UIPreferredContentSizeCategoryName` nor `simctl ui content_size` reaches
///   a watch simulator. The spec's type is fixed-size, so this only moves system controls.
/// - `-dgWatchTestHost`: the `DaGymWatchTests` host — no store is opened and no HealthKit session
///   is started, so the runner attaches instantly and each suite owns its own container.
enum WatchLaunchFlags {
    static var isSample: Bool { has("-dgWatchSample") }

    static var isTestHost: Bool { has("-dgWatchTestHost") }

    static var forcesAlwaysOn: Bool { has("-dgWatchAlwaysOn") }

    static var forcesLargestText: Bool { has("-dgWatchTextSize") }

    static var screen: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-dgWatchScreen"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    private static func has(_ flag: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(flag)
        #else
        false
        #endif
    }
}
