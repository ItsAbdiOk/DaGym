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

    /// The table is a *curated* map, not a fallback: a name that says which equipment it used
    /// must never be answered with different equipment. These four all used to collapse onto the
    /// barbell (or alphabetically-first) seed, which merged a different lift's history into it and
    /// handed it that lift's personal records.
    @Test(
        "a known qualifier with no entry falls through instead of picking the wrong exercise",
        arguments: [
            "Squat (Bodyweight)", "Deadlift (Dumbbell)", "Shoulder Press (Machine)",
            "Bicep Curl (Cable)", "Bench Press (Machine)", "Hip Thrust (Machine)",
            "Lateral Raise (Cable)"
        ]
    )
    func knownButAbsentQualifierFallsThrough(name: String) {
        #expect(ImportAliases.seedID(for: name) == nil)
    }

    @Test("an unqualified name still takes the barbell default")
    func unqualifiedStillDefaults() {
        #expect(ImportAliases.seedID(for: "Deadlift") == "Barbell_Deadlift")
        #expect(ImportAliases.seedID(for: "Shoulder Press") == "Barbell_Shoulder_Press")
    }

    @Test("a qualifier the table does have is still honoured")
    func presentQualifiersStillResolve() {
        #expect(ImportAliases.seedID(for: "Shoulder Press (Dumbbell)") == "Dumbbell_Shoulder_Press")
        #expect(ImportAliases.seedID(for: "Lat Pulldown (Machine)") == "Wide-Grip_Lat_Pulldown")
        #expect(ImportAliases.seedID(for: "Pull Up (Bodyweight)") == "Pullups")
    }

    @Test("EZ-bar spelling variants fold onto the same entry")
    func ezBarVariants() {
        #expect(ImportAliases.seedID(for: "Skull Crusher (EZ Bar)") == "EZ-Bar_Skullcrusher")
        #expect(ImportAliases.seedID(for: "Skullcrusher (EZ-Bar)") == "EZ-Bar_Skullcrusher")
    }

    @Test("an unknown qualifier is treated as part of the name, not as equipment")
    func unknownQualifierIsNotEquipment() {
        // "(Paused)" isn't equipment, so the whole string is looked up and simply isn't in the
        // table — it must not be stripped and then resolved as a bare "Bench Press".
        #expect(ImportAliases.seedID(for: "Bench Press (Paused)") == nil)
    }
}
