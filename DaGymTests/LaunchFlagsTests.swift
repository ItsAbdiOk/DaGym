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
}
