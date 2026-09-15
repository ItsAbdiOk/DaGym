import Foundation
import Testing

@testable import GymCore

@Suite("Program template engine and draft validator")
struct ProgramTemplateTests {
    private let equipment: Set<String> = ["barbell", "dumbbell", "machine", "cable", "bodyweight"]

    private func request(
        goal: TrainingGoal = .hypertrophy, days: Int = 4, minutes: Int = 60,
        experience: ExperienceLevel = .intermediate, excludedEquipment: Set<String> = [],
        excludedMuscles: Set<Muscle> = []
    ) -> ProgramRequest {
        ProgramRequest(
            goal: goal, daysPerWeek: days, sessionMinutes: minutes, experience: experience,
            availableEquipment: equipment, excludedEquipment: excludedEquipment,
            excludedMuscles: excludedMuscles
        )
    }

    /// A small library with a compound and an isolation move for every muscle the templates use.
    private func library() -> [SubstitutionCandidate] {
        var result: [SubstitutionCandidate] = []
        for muscle in Muscle.allCases {
            result.append(SubstitutionCandidate(
                id: UUID(), name: "Barbell \(muscle.displayName) compound", primary: [muscle],
                equipment: "barbell", mechanic: "compound"
            ))
            result.append(SubstitutionCandidate(
                id: UUID(), name: "Cable \(muscle.displayName) isolation", primary: [muscle],
                equipment: "cable", mechanic: "isolation"
            ))
            result.append(SubstitutionCandidate(
                id: UUID(), name: "Machine \(muscle.displayName) press", primary: [muscle],
                equipment: "machine", mechanic: "compound"
            ))
        }
        return result
    }

    @Test("every goal, day count and experience produces a balanced template inside its own bounds")
    func templatesAreBalanced() {
        for goal in TrainingGoal.allCases {
            for days in ProgramRequest.daysRange {
                for experience in ExperienceLevel.allCases {
                    for minutes in [30, 45, 60, 90] {
                        let template = ProgramTemplateEngine.template(
                            for: request(goal: goal, days: days, minutes: minutes, experience: experience)
                        )
                        #expect(template.days.count == days)
                        #expect(template.days.allSatisfy { (4...7).contains($0.slots.count) })
                        for muscle in template.trackedMuscles {
                            let sets = template.templateWeeklySets(for: muscle)
                            #expect(template.weeklySetBounds.contains(sets))
                        }
                    }
                }
            }
        }
    }

    @Test("goal decides sets, reps and the progression rule")
    func goalDecidesScheme() {
        let strength = ProgramTemplateEngine.template(for: request(goal: .strength))
        #expect(strength.rule == .linear(incrementKg: 2.5))
        let compound = strength.slots.first { $0.mechanic == "compound" }
        #expect(compound?.sets == 4 && compound?.repLow == 3 && compound?.repHigh == 5)

        let hypertrophy = ProgramTemplateEngine.template(for: request(goal: .hypertrophy))
        #expect(hypertrophy.rule == .doubleProgression(low: 8, high: 12, incrementKg: 2.5))
        let isolation = hypertrophy.slots.first { $0.mechanic == "isolation" }
        #expect(isolation?.repLow == 10 && isolation?.repHigh == 15)

        let advanced = ProgramTemplateEngine.template(for: request(goal: .strength, experience: .advanced))
        #expect(advanced.slots.first { $0.mechanic == "compound" }?.sets == 5)
    }

    @Test("an excluded muscle gets no slot, and a beginner is capped at five exercises")
    func exclusionsAndCaps() {
        let template = ProgramTemplateEngine.template(for: request(days: 4, excludedMuscles: [.lowerBack]))
        #expect(!template.trackedMuscles.contains(.lowerBack))
        let beginner = ProgramTemplateEngine.template(for: request(minutes: 90, experience: .beginner))
        #expect(beginner.days.allSatisfy { $0.slots.count == 5 })
    }

    @Test("the default picks fill every slot and pass the validator")
    func defaultPicksAreValid() throws {
        let request = request()
        let template = ProgramTemplateEngine.template(for: request)
        let pool = ProgramExercisePool.candidates(for: template, library: library(), request: request)
        let draft = try #require(ProgramDefaultPicks.draft(template: template, pool: pool, request: request))
        #expect(draft.picks.count == template.slots.count)
        #expect(draft.picks.map(\.slotID) == template.slots.map(\.id))
        _ = try ProgramDraftValidator.validate(draft, template: template, pool: pool, request: request)
        // A compound slot took the barbell; an isolation slot took the cable.
        let poolByID = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        let firstPick = try #require(draft.exerciseID(for: template.slots[0].id))
        #expect(poolByID[firstPick]?.equipment == "barbell")
    }

    @Test("the pool honours excluded equipment and muscles")
    func poolHonoursExclusions() {
        let request = request(excludedEquipment: ["barbell"], excludedMuscles: [.abs])
        let template = ProgramTemplateEngine.template(for: request)
        let pool = ProgramExercisePool.candidates(for: template, library: library(), request: request)
        #expect(!pool.isEmpty)
        #expect(pool.allSatisfy { $0.equipment != "barbell" })
        #expect(pool.allSatisfy { !$0.primary.contains(.abs) })
    }

    @Test("the pool and the validator only use stations the profile has")
    func poolHonoursStations() throws {
        let request = ProgramRequest(
            goal: .hypertrophy, daysPerWeek: 4, sessionMinutes: 60, experience: .intermediate,
            availableEquipment: equipment,
            equipmentAvailability: EquipmentAvailability(
                types: equipment, restrictsMachines: true, machines: [.chestPressMachine]
            )
        )
        let template = ProgramTemplateEngine.template(for: request)
        var stationed = library()
        // Every machine row needs a station; only the chest press is there.
        stationed = stationed.map { candidate in
            var copy = candidate
            if copy.equipment == "machine" {
                copy.machine = copy.primary == [.chest] ? "chestPressMachine" : "legPress"
            }
            return copy
        }
        let pool = ProgramExercisePool.candidates(for: template, library: stationed, request: request)
        #expect(!pool.isEmpty)
        #expect(pool.allSatisfy { $0.machine == nil || $0.machine == "chestPressMachine" })
        #expect(pool.contains { $0.machine == "chestPressMachine" })

        let legPress = try #require(stationed.first { $0.machine == "legPress" })
        let slot = try #require(template.slots.first { legPress.primary.contains($0.muscle) })
        let draft = ProgramDraft(name: "Legs", picks: [ProgramPick(slotID: slot.id, exerciseID: legPress.id)])
        #expect(throws: ProgramDraftError.excludedEquipment(legPress.id)) {
            try ProgramDraftValidator.validate(
                draft, template: template, pool: pool + [legPress], request: request
            )
        }
    }

    @Test("a foreign id, a wrong muscle, an excluded equipment and a missing slot are each refused")
    func validatorRefusals() throws {
        let request = request()
        let template = ProgramTemplateEngine.template(for: request)
        let pool = ProgramExercisePool.candidates(for: template, library: library(), request: request)
        let good = try #require(ProgramDefaultPicks.draft(template: template, pool: pool, request: request))

        var foreign = good
        foreign.picks[0].exerciseID = UUID()
        #expect(throws: ProgramDraftError.foreignExercise(foreign.picks[0].exerciseID)) {
            try ProgramDraftValidator.validate(foreign, template: template, pool: pool, request: request)
        }

        var wrong = good
        let slot = template.slots[0]
        let other = try #require(pool.first { !$0.primary.contains(slot.muscle) })
        wrong.picks[0].exerciseID = other.id
        #expect(throws: ProgramDraftError.wrongMuscle(slotID: slot.id)) {
            try ProgramDraftValidator.validate(wrong, template: template, pool: pool, request: request)
        }

        var missing = good
        missing.picks.removeLast()
        let lastSlot = try #require(template.slots.last)
        #expect(throws: ProgramDraftError.missingSlot(lastSlot.id)) {
            try ProgramDraftValidator.validate(missing, template: template, pool: pool, request: request)
        }

        var unnamed = good
        unnamed.name = "  "
        #expect(throws: ProgramDraftError.emptyName) {
            try ProgramDraftValidator.validate(unnamed, template: template, pool: pool, request: request)
        }

        // Same picks, but the lifter has since excluded barbells: the pool still lists one (it
        // was built before), so the equipment rule has to catch it on its own.
        let stricter = self.request(excludedEquipment: ["barbell"])
        #expect(throws: ProgramDraftError.self) {
            try ProgramDraftValidator.validate(good, template: template, pool: pool, request: stricter)
        }
    }

    @Test("an unbalanced draft — every slot the same overlapping lift — is refused on volume")
    func volumeBoundsEnforced() throws {
        let request = request(days: 6, minutes: 90, experience: .advanced)
        let template = ProgramTemplateEngine.template(for: request)
        // One lift that claims every tracked muscle as primary: its sets pile onto each of them.
        let everything = SubstitutionCandidate(
            id: UUID(), name: "Everything", primary: Array(template.trackedMuscles),
            equipment: "barbell", mechanic: "compound"
        )
        let picks = template.slots.map { ProgramPick(slotID: $0.id, exerciseID: everything.id) }
        let draft = ProgramDraft(name: "Too much", picks: picks)
        #expect(throws: ProgramDraftError.self) {
            try ProgramDraftValidator.validate(
                draft, template: template, pool: [everything], request: request
            )
        }
    }
}
