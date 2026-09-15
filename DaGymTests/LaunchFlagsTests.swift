import Foundation
import Testing
@testable import DaGym

@Suite("LaunchFlags")
struct LaunchFlagsTests {
    @Test("the unit-test host is recognised as a test process")
    func hostIsRecognised() {
        #expect(LaunchFlags.isUnitTestHost)
        #expect(LaunchFlags.isTesting)
    }

    /// Pins the scheme's `commandLineArguments["-dgTestHost"]` (`project.yml`) as actually
    /// plumbed through, independent of whichever XCTest-environment fallback also happens to
    /// fire (T3/finding 3) — delete the flag from the scheme and only this test notices.
    @Test("the DaGym scheme launches unit tests with -dgTestHost")
    func schemePassesTestHostFlag() {
        #expect(ProcessInfo.processInfo.arguments.contains("-dgTestHost"))
    }

    /// The test host is launched without `-dgInitCloudKitSchema`, so the flag is off; and it is
    /// `#if DEBUG` like every other launch flag — in Release the body is the literal `false`,
    /// which `releaseBuildCompilesFlagOut` pins by mirroring the same gate.
    @Test("-dgInitCloudKitSchema is off unless passed, and compiled out of Release")
    func schemaInitFlagIsDebugOnly() {
        #expect(!LaunchFlags.initializesCloudKitSchema)
        #if DEBUG
        #expect(
            LaunchFlags.initializesCloudKitSchema
                == ProcessInfo.processInfo.arguments.contains("-dgInitCloudKitSchema")
        )
        #else
        #expect(!LaunchFlags.initializesCloudKitSchema)
        #endif
    }
}
