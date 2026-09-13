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
}
