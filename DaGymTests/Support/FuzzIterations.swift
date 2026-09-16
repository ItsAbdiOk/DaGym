import Foundation

// Iteration count for the hosted property tests (`FuzzImportApplyTests`): 50 mutations per test
// by default so the bundle stays quick, more when the gate sets `DAGYM_TEST_FUZZ_ITERATIONS`
// (a positive integer). The test host only sees variables xcodebuild forwards, so set it as
// `TEST_RUNNER_DAGYM_TEST_FUZZ_ITERATIONS=500 xcodebuild test …`. The same variable drives the
// `GymCoreTests` fuzz suites (`FuzzSupport.swift`), where a plain `swift test` inherits it.
// Every generator is seeded, so a failure at any count is reproducible from the seed and the
// iteration index it reports.

/// The per-test mutation count, from `DAGYM_TEST_FUZZ_ITERATIONS` or the quick default.
enum FuzzIterations {
    static let quick = 50

    static let count: Int = {
        let raw = ProcessInfo.processInfo.environment["DAGYM_TEST_FUZZ_ITERATIONS"] ?? ""
        guard let value = Int(raw), value > 0 else { return quick }
        return value
    }()
}
