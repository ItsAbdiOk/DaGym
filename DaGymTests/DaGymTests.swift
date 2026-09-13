import Testing
@testable import DaGym

@Suite("App target")
struct DaGymTests {
    @Test("test bundle links against the app")
    func links() {
        #expect(Bool(true))
    }
}
