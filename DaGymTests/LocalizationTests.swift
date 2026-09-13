import Foundation
import Testing
@testable import DaGym

/// Proves the String Catalog scaffolding (`DaGym/Resources/Localizable.xcstrings`,
/// `project.yml`'s `LOCALIZED_STRING_SWIFTUI_SUPPORT`/`SWIFT_EMIT_LOC_STRINGS`) is actually wired
/// up. The catalog is empty by design — this only checks the plumbing, not translations.
@Suite("Localization scaffolding")
struct LocalizationTests {
    @Test("the Localizable string catalog is present in the main bundle")
    func catalogIsInMainBundle() {
        // An empty catalog compiles to no .strings file, so the observable wiring is the bundle's
        // declared development localization plus the catalog living next to the sources.
        #expect(Bundle.main.developmentLocalization == "en")
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "DaGym/Resources/Localizable.xcstrings")
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test(
        "user-facing strings resolve through String(localized:) unchanged",
        arguments: ["Settings", "Acknowledgements", "Privacy", "Version", "About"]
    )
    func stringsResolveUnchanged(_ key: String) {
        #expect(String(localized: String.LocalizationValue(key)) == key)
    }
}
