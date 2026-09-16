import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The seed's `machine` column: every machine-kind row is tagged (or explicitly excused), every
/// tag is a real station whose kind agrees with the row's, and every station's picture exists.
@Suite("Seed machine data")
struct SeedMachineDataTests {
    /// Machine-kind rows with no station in the taxonomy, mirrored from
    /// `scripts/import-exercises.py` `UNTAGGED_MACHINE_ROWS` — each with its reason there.
    private let untaggedMachineRows: Set<String> = [
        "Chair_Squat", "Lunge_Sprint", "Leverage_Deadlift", "Leverage_Shrug", "Reverse_Hyperextension"
    ]

    @Test("every machine-kind row carries a station, except the excused few")
    func machineRowsAreTagged() throws {
        let seed = try ExerciseSeeder.loadSeed()
        #expect(seed.version == 5)
        let untagged = seed.exercises.filter { $0.equipment == "machine" && $0.machine == nil }.map(\.id)
        #expect(Set(untagged) == untaggedMachineRows, "\(untagged)")
        let taggedCount = seed.exercises.filter { $0.machine != nil }.count
        #expect(taggedCount > 300)
    }

    @Test("rows land on the station a lifter looks for them under, and the Smith rows are machine-kind")
    func stationsMatchTheFloor() throws {
        let rows = Dictionary(
            uniqueKeysWithValues: try ExerciseSeeder.loadSeed().exercises.map { ($0.id, $0) }
        )
        let expected: [String: Machine] = [
            "Dip_Machine": .seatedDipMachine, "Glute_Ham_Raise": .gluteHamDeveloper,
            "Machine_Lateral_Raise": .lateralRaiseMachine, "Pullover_Machine": .pulloverMachine,
            "Seated_Bench_Press": .chestPressMachine, "Ski_Machine": .skiErg, "Belt_Squat": .beltSquat,
            "Single_Arm_Lat_Pulldown": .latPulldown, "1_Arm_Half_Kneeling_Lat_Pulldown": .cableStation,
            "V-Bar_Pulldown": .latPulldown, "Rowing_T_bar": .rowMachine,
            "Rowing_seated_narrow_grip": .seatedRowMachine, "Shoulder_Press_on_Multi_Press": .smithMachine,
            "Calf-Machine_Shoulder_Shrug": .calfRaiseMachine, "Close_grip_Lat_Pull_Down": .latPulldown
        ]
        for (id, machine) in expected {
            #expect(rows[id]?.machine == machine.rawValue, "\(id) → \(rows[id]?.machine ?? "nil")")
        }
        for id in ["Ball_Leg_Curl", "Rowing_with_TRX_band", "Sitting_Calf_Stretch_Dorsiflexion"] {
            #expect(rows[id]?.machine == nil, "\(id) should carry no station")
        }
        for id in ["Smith_Machine_Split_Squat", "Smith_Incline_Shoulder_Raise"] {
            #expect(rows[id]?.equipment == "machine", "\(id) is a Smith move, not a barbell one")
            #expect(rows[id]?.machine == "smithMachine")
        }
    }

    @Test("every tag is a real station whose kind agrees with the row, or the row is a catch-all kind")
    func tagsAgreeWithKind() throws {
        let seed = try ExerciseSeeder.loadSeed()
        for item in seed.exercises {
            guard let raw = item.machine else { continue }
            let machine = try #require(Machine(rawValue: raw), "\(item.id) names unknown station \(raw)")
            // "other" and "bodyweight" are where the source filed its untyped machine rows
            // ("Leverage Machine Chest Press" is bodyweight); a station there is a refinement.
            // A free-weight kind must never carry one.
            let catchAll = ["other", "bodyweight"].contains(item.equipment)
            #expect(
                machine.equipmentType == item.equipment || catchAll,
                "\(item.id) is \(item.equipment) but tagged \(raw)"
            )
        }
    }

    @Test("every station's representative exercise is seeded and has bundled photographs")
    func representativePhotosExist() throws {
        let seedIDs = Set(try ExerciseSeeder.loadSeed().exercises.map(\.id))
        for machine in Machine.allCases {
            guard let seedID = machine.representativeExerciseSeedID else { continue }
            #expect(seedIDs.contains(seedID), "\(machine) → \(seedID) is not in the seed")
            let hasPhoto = ExercisePhotoStore.bundledURLs(forSeedID: seedID) != nil
            #expect(hasPhoto, "\(machine) → \(seedID) has no photo")
        }
    }
}

@MainActor
@Suite("Machine filtering")
struct MachineFilteringTests {
    @discardableResult
    private func exercise(
        _ store: WorkoutStore, _ name: String, equipment: String, machine: String? = nil,
        primary: Muscle = .chest
    ) -> ExerciseInfo {
        store.createCustomExercise(
            name: name, primary: [primary], equipment: equipment, style: .weightReps, machine: machine
        )
    }

    @discardableResult
    private func gym(_ store: WorkoutStore, machines: [Machine]) -> EquipmentProfileInfo {
        store.createProfile(
            name: "Gym", isActive: true, availableEquipment: ["barbell", "machine", "cable"],
            restrictsMachines: true, availableMachines: machines.map(\.rawValue)
        )
    }

    @Test("a profile's stations round-trip through the store and become one availability value")
    func profileRoundTrip() throws {
        let store = try makeStore()
        let profile = gym(store, machines: [.legPress, .cableStation])
        let read = try #require(store.equipmentProfiles().first { $0.id == profile.id })
        #expect(read.restrictsMachines)
        #expect(read.availableMachines == ["legPress", "cableStation"])
        #expect(read.availability.allows(equipment: "machine", machine: "legPress"))
        #expect(!read.availability.allows(equipment: "machine", machine: "pecDeck"))
        #expect(read.restrictsLibrary)

        var draft = EquipmentProfileDraft(name: "Gym", availableEquipment: read.availableEquipment)
        draft.restrictsMachines = false
        let updated = try #require(store.updateProfile(id: profile.id, draft: draft))
        #expect(!updated.restrictsMachines)
        #expect(updated.availableMachines.isEmpty)
        #expect(updated.availability.allows(equipment: "machine", machine: "pecDeck"))
    }

    @Test("the seeded Gym offers every station; the seeded Home none")
    func seededProfiles() throws {
        let store = try makeStore()
        EquipmentSeeder.seedIfNeeded(store: store)
        let gym = try #require(store.equipmentProfiles().first { $0.seedKey == "gym" })
        let home = try #require(store.equipmentProfiles().first { $0.seedKey == "home" })
        #expect(!gym.restrictsMachines)
        #expect(!gym.restrictsLibrary)
        #expect(home.restrictsMachines)
        #expect(home.availableMachines.isEmpty)
        #expect(!home.availability.allows(equipment: "bodyweight", machine: "pullUpBar"))
        #expect(home.availability.allows(equipment: "bodyweight", machine: nil))
    }

    @Test("a Home row seeded before stations existed still counts as untouched and folds")
    func legacyHomeStillFolds() throws {
        let store = try makeStore()
        EquipmentSeeder.seedIfNeeded(store: store)
        let legacy = EquipmentProfileModel(
            name: "Home", availableEquipment: ["dumbbell", "bodyweight", "bands"], seedKey: "home"
        )
        store.context.insert(legacy)
        store.save()
        #expect(store.dedupeEquipmentProfiles() == 1)
        #expect(store.equipmentProfiles().filter { $0.seedKey == "home" }.count == 1)
    }

    @Test("the picker hides by kind and by station, counts both, and 'show all' keeps the counts")
    func pickerFilter() throws {
        let store = try makeStore()
        let profile = gym(store, machines: [.legPress])
        let rows = [
            exercise(store, "Bench", equipment: "barbell"),
            exercise(store, "Fly", equipment: "dumbbell"),
            exercise(store, "Leg Press", equipment: "machine", machine: "legPress"),
            exercise(store, "Pec Deck", equipment: "machine", machine: "pecDeck"),
            exercise(store, "Crossover", equipment: "cable", machine: "cableStation"),
            exercise(store, "Some machine", equipment: "machine")
        ]
        var hidden = HiddenCounts()
        let visible = ExercisePickerFilter.visible(
            rows, availability: profile.availability, showingAll: false, hidden: &hidden
        )
        #expect(visible.map(\.name) == ["Bench", "Leg Press", "Some machine"])
        #expect(hidden == HiddenCounts(byType: 1, byMachine: 2))
        let all = ExercisePickerFilter.visible(
            rows, availability: profile.availability, showingAll: true, hidden: &hidden
        )
        #expect(all.count == rows.count)
        #expect(hidden == HiddenCounts(byType: 1, byMachine: 2))
        let title = EquipmentFilterBanner.title(profileName: "Gym", hidden: hidden, showingAll: false)
        #expect(title == "Showing what's in Gym · hiding 1 by equipment, 2 by machine")
        #expect(EquipmentFilterBanner.title(profileName: "Gym", hidden: HiddenCounts(), showingAll: false)
            == "Showing what's in Gym")
    }

    @Test("a routine's warning names the missing kinds then the missing stations, once each")
    func routineNeeds() throws {
        let store = try makeStore()
        let profile = gym(store, machines: [.legPress])
        let routine = store.saveRoutine(
            id: nil, name: "Legs",
            exercises: [
                exercise(store, "Leg Press", equipment: "machine", machine: "legPress"),
                exercise(store, "Pec Deck", equipment: "machine", machine: "pecDeck"),
                exercise(store, "Fly", equipment: "dumbbell"),
                exercise(store, "Pec Deck 2", equipment: "machine", machine: "pecDeck"),
                exercise(store, "Curl", equipment: "machine", machine: "legCurl")
            ].map { RoutineExerciseDraft(exerciseID: $0.id) }
        )
        let needs = routine.needs(outside: profile.availability)
        #expect(needs.types == ["dumbbell"])
        #expect(needs.machines == [.pecDeck, .legCurl])
        #expect(needs.displayNames == ["dumbbell", "pec deck", "leg curl"])
        #expect(routine.equipmentOutside(["machine"]) == ["dumbbell"])
    }

    @Test("substitution candidates never leave the profile's stations")
    func substitutionsRespectStations() throws {
        let store = try makeStore()
        gym(store, machines: [.chestPressMachine, .cableStation])
        let bench = exercise(store, "Bench", equipment: "barbell")
        exercise(store, "Pec Deck", equipment: "machine", machine: "pecDeck")
        exercise(store, "Chest Press", equipment: "machine", machine: "chestPressMachine")
        exercise(store, "Crossover", equipment: "cable", machine: "cableStation")
        exercise(store, "Pulldown", equipment: "cable", machine: "latPulldown", primary: .lats)
        let names = store.scoredSubstitutes(for: bench.id, reason: .shortOnTime).map(\.candidate.name)
        #expect(names.contains("Chest Press"))
        #expect(names.contains("Crossover"))
        #expect(!names.contains("Pec Deck"))
    }

    @Test("the program generator's pool only holds stations the profile has")
    func programPoolRespectsStations() throws {
        let store = try makeStore()
        gym(store, machines: [.legPress])
        for muscle in Muscle.allCases {
            exercise(store, "Barbell \(muscle.rawValue)", equipment: "barbell", primary: muscle)
            let key = muscle.rawValue
            exercise(store, "LP \(key)", equipment: "machine", machine: "legPress", primary: muscle)
            exercise(store, "PD \(key)", equipment: "machine", machine: "pecDeck", primary: muscle)
        }
        let request = ProgramRequest(
            goal: .hypertrophy, daysPerWeek: 4, sessionMinutes: 60, experience: .intermediate,
            availableEquipment: store.equipmentKindsForProgram(),
            equipmentAvailability: store.equipmentAvailabilityForProgram()
        )
        #expect(request.equipmentAvailability.restrictsMachines)
        let pool = store.programPool(for: ProgramTemplateEngine.template(for: request), request: request)
        #expect(!pool.isEmpty)
        #expect(pool.contains { $0.machine == "legPress" })
        #expect(pool.allSatisfy { $0.machine != "pecDeck" })
    }

    @Test("a seed bump copies the station onto existing rows but never over a lifter's own tag")
    func seederCopiesMachine() throws {
        let context = try makeContext(seed: .exercises)
        let rows = try context.fetch(FetchDescriptor<ExerciseModel>())
        let legPress = try #require(rows.first { $0.seedID == "Leg_Press" })
        let pecDeck = try #require(rows.first { $0.seedID == "Butterfly" })
        #expect(legPress.machine == "legPress")
        // Pretend both rows predate seed v5: one untagged, one the lifter re-tagged themselves.
        legPress.machine = nil
        pecDeck.machine = "chestPressMachine"
        SeedState.row(in: context).exerciseSeedVersion = 4
        try context.save()
        ExerciseSeeder.seedIfNeeded(context: context)
        #expect(SeedState.row(in: context).exerciseSeedVersion == 5)
        #expect(legPress.machine == "legPress")
        #expect(pecDeck.machine == "chestPressMachine")
    }

    @Test("a backup carries a custom exercise's station and a profile's station list")
    func backupRoundTrip() throws {
        let source = try makeStore()
        gym(source, machines: [.legPress, .pullUpBar])
        let custom = exercise(source, "My Press", equipment: "machine", machine: "chestPressMachine")
        let document = BackupService.export(context: source.context)
        #expect(document.exercises.first { $0.id == custom.id }?.machine == "chestPressMachine")
        #expect(document.equipmentProfiles.first?.availableMachines == ["legPress", "pullUpBar"])

        let destination = try makeStore()
        BackupService.import(document: document, context: destination.context)
        let restored = try #require(destination.equipmentProfiles().first)
        #expect(restored.restrictsMachines)
        #expect(restored.availableMachines == ["legPress", "pullUpBar"])
        let restoredExercise = try #require(destination.exercises(matching: "My Press").first)
        #expect(restoredExercise.machine == "chestPressMachine")
    }

    @Test("the profile editor's selection: All is unrestricted, one off restricts, None is none")
    func machineSelection() {
        var selection = MachineSelection()
        #expect(selection.isOn(.pecDeck))
        #expect(!selection.restrictsMachinesForSave)
        selection.set(.pecDeck, on: false)
        #expect(selection.restrictsMachinesForSave)
        #expect(!selection.isOn(.pecDeck))
        #expect(selection.isOn(.legPress))
        #expect(!selection.availableMachinesForSave.contains("pecDeck"))
        #expect(selection.count(ofTypes: ["machine"]).on == Machine.machines(ofType: "machine").count - 1)
        selection.set(.pecDeck, on: true)
        #expect(!selection.restrictsMachinesForSave)
        #expect(selection.availableMachinesForSave.isEmpty)
        selection.setAll(ofTypes: ["cable"], on: false)
        #expect(selection.restrictsMachinesForSave)
        #expect(selection.isOn(.legPress))
        #expect(!selection.isOn(.latPulldown))
        #expect(selection.count(ofTypes: ["cable"]) == (0, 3))
        let home = MachineSelection(profile: EquipmentProfileInfo(
            id: UUID(), name: "Home", isActive: true, barKg: 20, availableEquipment: ["bodyweight"],
            plateStock: [], collarsKg: 0, restrictsMachines: true, availableMachines: []
        ))
        #expect(!home.isOn(.pullUpBar))
        #expect(home.restrictsMachinesForSave)
    }
}
