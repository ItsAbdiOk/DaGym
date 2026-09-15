import Foundation
import GymCore
import Testing

@testable import DaGym

/// A proposal goes propose → validate → apply → undo and leaves the store as it was; a
/// proposal the gym cannot do, or whose routine has gone, is refused with a reason.
@MainActor
@Suite("Coach chat apply and undo")
struct CoachChatApplyTests {
    @Test("propose_routine round-trips into a saved routine and undo removes it")
    func routineRoundTrip() async throws {
        let fixture = try CoachChatToolFixture.make()
        let json = """
        {"name":" Pull Day ","rule":"linear","notes":"Rows first.","exercises":[
          {"exercise_name":"dumbbell row","sets":[{"target_reps":10,"target_weight_kg":30,"rpe":8},
                                                  {"target_reps":10,"target_weight_kg":30}],
           "rest_seconds":90,"superset_group":1},
          {"exercise_id":"\(fixture.bench.id.uuidString)","sets":[{"kind":"warmup","target_reps":5},
                                                                  {"target_reps":6}]}
        ]}
        """
        let draft = try await fixture.draft(.proposeRoutine, json)
        guard case .routine(let proposal) = draft else {
            Issue.record("expected a routine")
            return
        }
        #expect(proposal.name == "Pull Day")
        #expect(proposal.exercises.map(\.exerciseName) == ["Dumbbell Row", "Bench Press"])
        #expect(proposal.exercises[0].exerciseID == fixture.row.id)

        let application = try fixture.store.apply(draft)
        guard case .routine(let id, let name) = application else {
            Issue.record("expected a routine application")
            return
        }
        #expect(name == "Pull Day")
        #expect(application.message == "Saved Pull Day")
        let (info, drafts) = try #require(fixture.store.routineDrafts(id: id))
        #expect(info.exercises.map(\.name) == ["Dumbbell Row", "Bench Press"])
        #expect(drafts[0].sets.count == 2)
        #expect(drafts[0].sets[0].targetWeightKg == 30)
        #expect(drafts[0].sets[0].targetRPE == 8)
        #expect(drafts[0].restOverrideSeconds == 90)
        #expect(drafts[0].supersetGroup == 1)
        #expect(drafts[1].sets[0].kind == .warmup)
        #expect(fixture.store.fetchRoutineModel(id: id)?.notes == "Rows first.")
        #expect(fixture.store.fetchRoutineModel(id: id)?.progressionRuleValue == .linear(incrementKg: 2.5))
        #expect(fixture.store.routines().count == 2)

        fixture.store.undo(application)
        #expect(fixture.store.routines().count == 1)
        #expect(fixture.store.routine(id: id) == nil)
    }

    @Test("a routine needing a machine the gym lacks is rejected with the station named")
    func unavailableMachineRejected() async throws {
        let fixture = try CoachChatToolFixture.make()
        let json = #"{"name":"Legs","exercises":[{"exercise_name":"Leg Press","sets":[{"target_reps":10}]}]}"#
        await #expect(throws: CoachChatToolError.rejected([
            "'Leg Press' needs a Leg Press, which the lifter's gym does not have."
        ])) {
            try await fixture.executor.execute(name: "propose_routine", argumentsJSON: json)
        }
    }

    @Test("every problem is listed at once so the model can fix them in one retry")
    func allReasonsListed() async throws {
        let fixture = try CoachChatToolFixture.make()
        let json = #"{"name":"","exercises":[{"exercise_name":"Nope","sets":[{"target_reps":8}]},"#
            + #"{"exercise_name":"Bench Press","sets":[{"target_reps":99}]}]}"#
        do {
            _ = try await fixture.executor.execute(name: "propose_routine", argumentsJSON: json)
            Issue.record("expected a rejection")
        } catch CoachChatToolError.rejected(let reasons) {
            #expect(reasons.count == 3)
            #expect(reasons.contains("The routine needs a name."))
            #expect(reasons.contains { $0.hasPrefix("Unknown exercise 'Nope'") })
            #expect(reasons.contains("'Bench Press' asks for 99 reps; use 1–50."))
        }
    }

    @Test("propose_schedule needs live routine ids; apply replaces the weekdays and undo restores")
    func scheduleRoundTrip() async throws {
        let fixture = try CoachChatToolFixture.make()
        let routine = fixture.routine.id.uuidString
        await #expect(throws: CoachChatToolError.self) {
            try await fixture.executor.execute(
                name: "propose_schedule", argumentsJSON: #"{"days":{"monday":"\#(UUID().uuidString)"}}"#
            )
        }
        let draft = try await fixture.draft(
            .proposeSchedule, #"{"days":{"tuesday":"\#(routine)","friday":"\#(routine)"}}"#
        )
        #expect(draft.summary == "Tue Push, Fri Push")
        let application = try fixture.store.apply(draft)
        #expect(Set(fixture.store.schedule().dayRoutines.keys) == [.tuesday, .friday])
        fixture.store.undo(application)
        #expect(Set(fixture.store.schedule().dayRoutines.keys) == [.monday, .thursday])
    }

    @Test("propose_deload cuts the last working weight by the percent; undo restores the plan")
    func deloadRoundTrip() async throws {
        let fixture = try CoachChatToolFixture.make()
        let draft = try await fixture.draft(.proposeDeload, #"{"exercise_name":"Bench Press","percent":10}"#)
        #expect(draft.summary == "Deload Bench Press by 10%")
        let application = try fixture.store.apply(draft)
        #expect(application.message == "Bench Press deloaded")
        let (_, drafts) = try #require(fixture.store.routineDrafts(id: fixture.routine.id))
        // 10 % off 80 kg is 72 kg, rounded onto the plate grid (2.5 kg steps) as 70 kg.
        #expect(drafts[0].sets.map(\.targetWeightKg) == [70, 70, 70])
        fixture.store.undo(application)
        let (_, restored) = try #require(fixture.store.routineDrafts(id: fixture.routine.id))
        #expect(restored[0].sets.map(\.targetWeightKg) == [60, 60, 60])

        let unprogrammed = #"{"exercise_name":"Leg Press","percent":10}"#
        await #expect(throws: CoachChatToolError.rejected([
            "No routine programs 'Leg Press', so there is nothing to deload."
        ])) {
            try await fixture.executor.execute(name: "propose_deload", argumentsJSON: unprogrammed)
        }
    }

    @Test("propose_swap replaces the slot keeping its sets; undo puts the old exercise back")
    func swapRoundTrip() async throws {
        let fixture = try CoachChatToolFixture.make()
        let extra = fixture.store.createCustomExercise(
            name: "Incline Press", primary: [.chest], equipment: "dumbbell", style: .weightReps
        )
        let json = """
        {"routine_id":"\(fixture.routine.id.uuidString)","from_exercise_name":"Bench Press",
         "to_exercise_id":"\(extra.id.uuidString)"}
        """
        let draft = try await fixture.draft(.proposeSwap, json)
        #expect(draft.summary == "Swap Bench Press → Incline Press in Push")
        let application = try fixture.store.apply(draft)
        let (info, drafts) = try #require(fixture.store.routineDrafts(id: fixture.routine.id))
        #expect(info.exercises.map(\.name) == ["Incline Press", "Dumbbell Row"])
        #expect(drafts[0].sets.map(\.targetWeightKg) == [60, 60, 60])
        fixture.store.undo(application)
        let (restored, _) = try #require(fixture.store.routineDrafts(id: fixture.routine.id))
        #expect(restored.exercises.map(\.name) == ["Bench Press", "Dumbbell Row"])

        let wrongRoutine = #"{"routine_id":"\#(UUID().uuidString)","from_exercise_name":"Bench Press"}"#
        await #expect(throws: CoachChatToolError.self) {
            try await fixture.executor.execute(name: "propose_swap", argumentsJSON: wrongRoutine)
        }
    }

    @Test("a draft whose routine was deleted after proposing is refused at apply")
    func staleRoutineRefused() async throws {
        let fixture = try CoachChatToolFixture.make()
        let routine = fixture.routine.id.uuidString
        let schedule = try await fixture.draft(.proposeSchedule, #"{"days":{"monday":"\#(routine)"}}"#)
        let swap = try await fixture.draft(
            .proposeSwap,
            #"{"routine_id":"\#(routine)","from_exercise_name":"Bench Press","#
                + #""to_exercise_name":"Dumbbell Row"}"#
        )
        fixture.store.deleteRoutine(id: fixture.routine.id)
        #expect(throws: CoachChatApplyError.routineMissing) { try fixture.store.apply(schedule) }
        #expect(throws: CoachChatApplyError.routineMissing) { try fixture.store.apply(swap) }
    }

    @Test("propose_program with routines saves them under one program; undo deletes all of it")
    func programWithRoutines() async throws {
        let fixture = try CoachChatToolFixture.make()
        let json = """
        {"name":"Upper/Lower","goal":"hypertrophy","days_per_week":2,"routines":[
          {"name":"Upper","exercises":[{"exercise_name":"Bench Press","sets":[{"target_reps":8}]}]},
          {"name":"Pull","exercises":[{"exercise_name":"Dumbbell Row","sets":[{"target_reps":12}]}]}
        ]}
        """
        let draft = try await fixture.draft(.proposeProgram, json)
        #expect(draft.summary == "Upper/Lower — 2 days/week, 2 routines")
        let application = try fixture.store.apply(draft)
        guard case .program(let generated) = application else {
            Issue.record("expected a program")
            return
        }
        #expect(generated.routineIDs.count == 2)
        #expect(Set(fixture.store.routines().map(\.name)) == ["Push", "Upper", "Pull"])
        let programs = fixture.store.programs(now: fixture.now)
        let program = try #require(programs.first { $0.id == generated.programID })
        #expect(program.routineIDs == generated.routineIDs)
        #expect(program.weeks == ProgramTemplateEngine.weeks)
        fixture.store.undo(application)
        #expect(fixture.store.routines().map(\.name) == ["Push"])
        #expect(fixture.store.programs(now: fixture.now).contains { $0.id == generated.programID } == false)
    }

    @Test("a template program on a library too small for it fails at apply, not silently")
    func templateProgramNeedsPool() async throws {
        let fixture = try CoachChatToolFixture.make()
        let json = #"{"name":"UL","goal":"strength","days_per_week":4}"#
        let draft = try await fixture.draft(.proposeProgram, json)
        #expect(throws: CoachChatApplyError.programEmpty) { try fixture.store.apply(draft) }
    }

    @Test("lifter profile facts come from the store and the preferences handed in")
    func profileFacts() throws {
        let fixture = try CoachChatToolFixture.make()
        let facts = fixture.store.lifterProfileFacts(
            unit: .lb, weeklyGoal: 3, trainingGoal: .hypertrophy, now: fixture.now, calendar: fixture.calendar
        )
        #expect(facts.unit == .lb)
        #expect(facts.weeklyGoal == 3)
        #expect(facts.goal == .hypertrophy)
        #expect(facts.bodyweightKg == 80)
        #expect(facts.equipmentProfileName == "Home")
        #expect(facts.equipmentTypes == ["barbell", "dumbbell", "machine"])
        #expect(facts.restrictsMachines)
        #expect(facts.machines == ["Leg Curl"])
        #expect(facts.routineNames == ["Push"])
        #expect(facts.workoutsLast4Weeks == 2)
        #expect(facts.activeProgramName == nil)
        #expect(Preferences.TrainingGoal.muscle.coachGoal == .hypertrophy)
    }

    @Test("the chat configuration reads the two preferences and nothing else")
    func configuration() throws {
        let name = "CoachChatApplyTests.configuration"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(suite: defaults)
        #expect(CoachChatConfiguration(preferences: preferences) == CoachChatConfiguration())
        preferences.coachModelID = "openai/gpt-5"
        preferences.coachChatConsentGiven = true
        let configuration = CoachChatConfiguration(preferences: preferences)
        #expect(configuration.modelID == "openai/gpt-5")
        #expect(configuration.consentGiven)
        #expect(Preferences(suite: defaults).coachModelID == "openai/gpt-5")
        #expect(Preferences(suite: defaults).coachChatConsentGiven)
    }
}
