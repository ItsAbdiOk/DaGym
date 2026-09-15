import Foundation
import Testing
@testable import DaGym

/// `CloudKitSchemaInitializer` is `#if DEBUG` like the launch flag that drives it, so this
/// suite only compiles in Debug — the same configuration the test bundle always runs in.
@Suite("CloudKitSchemaInitializer")
struct CloudKitSchemaInitializerTests {
    @Test("refuses to touch CloudKit when there is no iCloud account")
    func refusesWithoutAccount() {
        let result = CloudKitSchemaInitializer.run(hasAccount: { false })
        #expect(!result.ok)
        #expect(result.error == "no iCloud account")
        #expect(result.recordTypes == 0)
    }

    @Test("marker file is the JSON the script parses")
    func markerRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "schema-init-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = CloudKitSchemaInitializer.Result(ok: false, error: "no iCloud account", recordTypes: 0)
        try CloudKitSchemaInitializer.write(result, to: url)
        let data = try Data(contentsOf: url)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["ok"] as? Bool == false)
        #expect(json["error"] as? String == "no iCloud account")
        #expect(json["recordTypes"] as? Int == 0)
        #expect(try JSONDecoder().decode(CloudKitSchemaInitializer.Result.self, from: data) == result)
    }

    @Test("marker lives in Documents, where simctl and devicectl can read it")
    func markerPath() {
        #expect(CloudKitSchemaInitializer.markerURL.lastPathComponent == "schema-init.json")
        #expect(CloudKitSchemaInitializer.markerURL.deletingLastPathComponent() == URL.documentsDirectory)
    }
}
