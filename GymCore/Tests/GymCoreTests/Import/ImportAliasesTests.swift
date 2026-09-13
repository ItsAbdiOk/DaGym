import Foundation
import Testing

@testable import GymCore

@Suite("ImportAliases")
struct ImportAliasesTests {
    @Test("an unqualified common name resolves to the barbell variant")
    func unqualifiedResolvesToBarbell() {
        #expect(ImportAliases.seedID(for: "Squat") == "Barbell_Squat")
    }

    @Test("a Hevy-style equipment qualifier resolves to the matching variant")
    func qualifiedResolvesToMatchingVariant() {
        #expect(ImportAliases.seedID(for: "Squat (Barbell)") == "Barbell_Squat")
    }

    @Test("a dumbbell qualifier picks the dumbbell seed id")
    func dumbbellQualifier() {
        #expect(ImportAliases.seedID(for: "Bicep Curl (Dumbbell)") == "Dumbbell_Bicep_Curl")
    }

    @Test("a name outside the curated table is unmatched")
    func unknownNameIsNil() {
        #expect(ImportAliases.seedID(for: "Zercher Squat") == nil)
    }
}
