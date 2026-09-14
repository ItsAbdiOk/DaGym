import Foundation
import Testing
@testable import DaGym

@MainActor
@Suite("PrivacyPolicyView")
struct PrivacyPolicyViewTests {
    @Test("loads PrivacyPolicy.md from the bundle and renders it as Markdown")
    func loadsMarkdownFromBundle() {
        let rendered = PrivacyPolicyView.loadMarkdown()
        let plain = String(rendered.characters)
        #expect(plain.contains("Privacy Policy"))
        #expect(plain.contains("mo.abdirahman99@gmail.com"))
    }
}
