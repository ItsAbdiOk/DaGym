import Foundation
import Testing

@testable import GymCore

@Suite("CoachChatDraft: validation against the library and the gym")
struct CoachChatDraftTests {
    private static let benchID = UUID()
    private static let legPressID = UUID()
    private static let rowID = UUID()
    private static let pullUpID = UUID()

    private let library = [
        SubstitutionCandidate(
            id: benchID, name: "Bench Press", primary: [.chest], equipment: "barbell", mechanic: "compound"
        ),
        SubstitutionCandidate(
            id: legPressID, name: "Leg Press", primary: [.quads], equipment: "machine", mechanic: "compound",
            machine: Machine.legPress.rawValue
        ),
        SubstitutionCandidate(
            id: rowID, name: "Cable Row", primary: [.lats], equipment: "cable", mechanic: "compound",
            machine: Machine.seatedRowMachine.rawValue
        ),
        SubstitutionCandidate(
            id: pullUpID, name: "Pull-Up", primary: [.lats], equipment: "bodyweight", mechanic: "compound",
            machine: Machine.pullUpBar.rawValue
        )
    ]

    /// Barbell, cable and bodyweight, but no machines at all and only a seated row among stations.
    private let homeGym = EquipmentAvailability(
        types: ["barbell", "cable", "bodyweight"], restrictsMachines: true, machines: [.seatedRowMachine]
    )
    private let fullGym = EquipmentAvailability(types: ["barbell", "machine", "cable", "bodyweight"])

    private func sets(_ count: Int, reps: Int = 8, kg: Double? = 60) -> [CoachChatSetSpec] {
        Array(repeating: CoachChatSetSpec(targetReps: reps, targetWeightKg: kg), count: count)
    }

    private func reasons(_ result: Result<CoachChatDraft, CoachChatDraftRejection>) -> [String] {
        switch result {
        case .success: []
        case .failure(let rejection): rejection.reasons
        }
    }

    @Test("a sound routine comes back canonical: ids filled, library spelling, trimmed name")
    func routineCanonical() throws {
        let draft = CoachChatDraft.routine(RoutineProposal(
            name: "  Upper A  ",
            exercises: [
                CoachChatExerciseSpec(exerciseName: "bench press", sets: sets(3)),
                CoachChatExerciseSpec(exerciseID: Self.rowID, sets: sets(3, kg: nil), restSeconds: 90)
            ],
            rule: .doubleProgression, notes: "  "
        ))
        let validated = try draft.validate(availability: homeGym, library: library).get()
        guard case .routine(let routine) = validated else { Issue.record("not a routine"); return }
        #expect(routine.name == "Upper A")
        #expect(routine.notes == nil)
        #expect(routine.exercises[0].exerciseID == Self.benchID)
        #expect(routine.exercises[0].exerciseName == "Bench Press")
        #expect(routine.exercises[1].exerciseName == "Cable Row")
        #expect(routine.summary == "Upper A — 2 exercises, 6 sets")
    }

    @Test("unknown exercises, missing machines and duplicates are all named")
    func routineRejections() {
        let draft = CoachChatDraft.routine(RoutineProposal(
            name: "Legs",
            exercises: [
                CoachChatExerciseSpec(exerciseName: "Pendlay Row", sets: sets(3)),
                CoachChatExerciseSpec(exerciseID: Self.legPressID, sets: sets(3)),
                CoachChatExerciseSpec(exerciseID: Self.pullUpID, sets: sets(3, kg: nil)),
                CoachChatExerciseSpec(exerciseName: "Bench Press", sets: sets(3)),
                CoachChatExerciseSpec(exerciseID: Self.benchID, sets: sets(3)),
                CoachChatExerciseSpec(sets: sets(3))
            ]
        ))
        let reasons = reasons(draft.validate(availability: homeGym, library: library))
        #expect(reasons.count == 5)
        #expect(reasons.contains { $0.contains("Unknown exercise 'Pendlay Row'") })
        #expect(reasons.contains { $0.contains("'Leg Press' needs machine") })
        #expect(reasons.contains { $0.contains("'Pull-Up' needs a Pull-Up Bar") })
        #expect(reasons.contains { $0.contains("'Bench Press' appears twice") })
        #expect(reasons.contains { $0.contains("needs an exercise_id or exercise_name") })
    }

    @Test("absurd set schemes are rejected")
    func setSchemes() {
        func routine(_ spec: CoachChatExerciseSpec) -> [String] {
            reasons(
                CoachChatDraft.routine(RoutineProposal(name: "X", exercises: [spec]))
                    .validate(availability: fullGym, library: library)
            )
        }
        let bench = Self.benchID
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: [])).count == 1)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: sets(11))).count == 1)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: sets(1, reps: 0))).count == 1)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: sets(1, reps: 51))).count == 1)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: sets(1, kg: 601))).count == 1)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: sets(1, kg: -5))).count == 1)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: sets(1, reps: 50, kg: 600))).isEmpty)
        let badRPE = CoachChatSetSpec(targetReps: 5, rpe: 11)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: [badRPE])).count == 1)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: sets(3), restSeconds: 601)).count == 1)
        #expect(routine(CoachChatExerciseSpec(exerciseID: bench, sets: sets(3), restSeconds: 90)).isEmpty)
    }

    @Test("an empty name and too many exercises are rejected")
    func routineShape() {
        let empty = CoachChatDraft.routine(RoutineProposal(name: " ", exercises: []))
        let reasons = reasons(empty.validate(availability: fullGym, library: library))
        #expect(reasons.count == 2)
        let many = Array(
            repeating: CoachChatExerciseSpec(exerciseID: Self.benchID, sets: sets(1)), count: 21
        )
        let tooMany = CoachChatDraft.routine(RoutineProposal(name: "Long", exercises: many))
        #expect(self.reasons(tooMany.validate(availability: fullGym, library: library)).count == 1)
    }

    @Test("a program validates each routine and prefixes its name; a template program needs none")
    func program() throws {
        let template = CoachChatDraft.program(ProgramProposal(name: "UL", goal: .strength, daysPerWeek: 4))
        let validated = try template.validate(availability: homeGym, library: library).get()
        #expect(validated.summary == "UL — 4 days/week, from the strength template")

        let explicit = CoachChatDraft.program(ProgramProposal(
            name: "UL", goal: .hypertrophy, daysPerWeek: 2, sessionMinutes: 20,
            routines: [
                RoutineProposal(
                    name: "Upper", exercises: [CoachChatExerciseSpec(exerciseID: Self.benchID, sets: sets(3))]
                ),
                RoutineProposal(
                    name: "Lower",
                    exercises: [CoachChatExerciseSpec(exerciseID: Self.legPressID, sets: sets(3))]
                ),
                RoutineProposal(
                    name: "upper", exercises: [CoachChatExerciseSpec(exerciseID: Self.rowID, sets: sets(3))]
                )
            ]
        ))
        let reasons = reasons(explicit.validate(availability: homeGym, library: library))
        #expect(reasons.contains { $0.hasPrefix("Lower: 'Leg Press' needs machine") })
        #expect(reasons.contains { $0.contains("session_minutes must be") })
        #expect(reasons.contains { $0.contains("2-day program cannot have 3 routines") })
        #expect(reasons.contains { $0.contains("share a name") })

        let badDays = CoachChatDraft.program(ProgramProposal(name: "X", goal: .general, daysPerWeek: 7))
        #expect(self.reasons(badDays.validate(availability: fullGym, library: library)).count == 1)
    }

    @Test("a schedule needs at least one day; its summary names routines Monday first")
    func schedule() throws {
        let upper = UUID()
        let draft = CoachChatDraft.schedule(ScheduleProposal(
            days: [.wednesday: upper, .monday: upper], routineNames: [upper: "Upper"]
        ))
        let validated = try draft.validate(availability: fullGym, library: library).get()
        #expect(validated.summary == "Mon Upper, Wed Upper")
        let empty = CoachChatDraft.schedule(ScheduleProposal(days: [:]))
        #expect(reasons(empty.validate(availability: fullGym, library: library)).count == 1)
    }

    @Test("a deload needs a known exercise and a sane percent; equipment is not checked")
    func deload() throws {
        let draft = CoachChatDraft.deload(DeloadProposal(exerciseName: "leg press", percent: 10))
        let validated = try draft.validate(availability: homeGym, library: library).get()
        guard case .deload(let deload) = validated else { Issue.record("not a deload"); return }
        #expect(deload.exerciseID == Self.legPressID)
        #expect(deload.summary == "Deload Leg Press by 10%")
        let bad = CoachChatDraft.deload(DeloadProposal(exerciseName: "Nothing", percent: 60))
        #expect(reasons(bad.validate(availability: fullGym, library: library)).count == 2)
    }

    @Test("a swap checks the replacement's equipment, not the outgoing exercise's, and refuses a no-op")
    func swap() throws {
        let routine = UUID()
        let draft = CoachChatDraft.swap(SwapProposal(
            routineID: routine, routineName: "Legs", fromExerciseID: Self.legPressID,
            toExerciseName: "Cable Row"
        ))
        let validated = try draft.validate(availability: homeGym, library: library).get()
        guard case .swap(let swap) = validated else { Issue.record("not a swap"); return }
        #expect(swap.toExerciseID == Self.rowID)
        #expect(swap.fromExerciseName == "Leg Press")
        #expect(swap.summary == "Swap Leg Press → Cable Row in Legs")

        let unavailable = CoachChatDraft.swap(SwapProposal(
            routineID: routine, fromExerciseID: Self.benchID, toExerciseID: Self.pullUpID
        ))
        #expect(reasons(unavailable.validate(availability: homeGym, library: library)).count == 1)
        let noop = CoachChatDraft.swap(SwapProposal(
            routineID: routine, fromExerciseID: Self.benchID, toExerciseName: "Bench Press"
        ))
        #expect(reasons(noop.validate(availability: fullGym, library: library)).count == 1)
    }

    @Test("every draft round-trips through JSON with the tool's snake_case keys")
    func codable() throws {
        let upper = UUID()
        let drafts: [CoachChatDraft] = [
            .routine(RoutineProposal(
                name: "A",
                exercises: [CoachChatExerciseSpec(exerciseID: Self.benchID, sets: sets(2), supersetGroup: 1)],
                rule: .linear, notes: "n"
            )),
            .program(ProgramProposal(name: "P", goal: .general, daysPerWeek: 3, experience: .beginner)),
            .schedule(ScheduleProposal(days: [.monday: upper], routineNames: [upper: "Upper"])),
            .deload(DeloadProposal(exerciseID: Self.benchID, percent: 10)),
            .swap(SwapProposal(routineID: upper, fromExerciseID: Self.benchID, toExerciseID: Self.rowID))
        ]
        for draft in drafts {
            let data = try JSONEncoder().encode(draft)
            #expect(try JSONDecoder().decode(CoachChatDraft.self, from: data) == draft)
        }
        let json = try #require(String(data: try JSONEncoder().encode(drafts[0]), encoding: .utf8))
        #expect(json.contains("\"exercise_id\""))
        #expect(json.contains("\"target_reps\""))
        #expect(json.contains("\"superset_group\""))
    }

    @Test("propose_schedule arguments decode weekday names; unknown days and bad ids are refused")
    func scheduleWire() throws {
        let upper = UUID()
        let good = Data(
            "{\"days\":{\"monday\":\"\(upper.uuidString)\",\"Friday\":\"\(upper.uuidString)\"}}".utf8
        )
        let proposal = try JSONDecoder().decode(ScheduleProposal.self, from: good)
        #expect(proposal.days == [.monday: upper, .friday: upper])
        let badDay = Data("{\"days\":{\"funday\":\"\(upper.uuidString)\"}}".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ScheduleProposal.self, from: badDay) }
        let badID = Data("{\"days\":{\"monday\":\"upper\"}}".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ScheduleProposal.self, from: badID) }
    }

    @Test("a set spec defaults to a working set when the model omits the kind")
    func setKindDefault() throws {
        let spec = try JSONDecoder().decode(CoachChatSetSpec.self, from: Data("{\"target_reps\":8}".utf8))
        #expect(spec.kind == .working)
        #expect(spec.targetWeightKg == nil)
    }

    @Test("rule choices map onto progression rules")
    func ruleChoices() {
        #expect(CoachChatRuleChoice.linear.progressionRule(incrementKg: 5) == .linear(incrementKg: 5))
        #expect(CoachChatRuleChoice.rpe.progressionRule() == .rpeBased(targetRPE: 8))
        #expect(
            CoachChatRuleChoice.bodyweight.progressionRule()
                == .bodyweight(
                    repCeiling: TrainingConstants.bodyweightRepCeiling,
                    maxSets: TrainingConstants.bodyweightMaxSets
                )
        )
    }
}
