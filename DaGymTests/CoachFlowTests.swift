import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The store side of the coach flows: program generation with undo, applying and undoing each
/// review change, the question tools, and the Siri intent's grounding fallback.
@MainActor
@Suite("Coach flows: program generator, review actions, questions")
struct CoachFlowTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    /// A barbell compound and a cable isolation move per muscle, so every template slot fills.
    private func seedLibrary(_ store: WorkoutStore) {
        for muscle in Muscle.allCases {
            _ = store.createCustomExercise(
                name: "Barbell \(muscle.displayName)", primary: [muscle], equipment: "barbell",
                style: .weightReps
            )
            _ = store.createCustomExercise(
                name: "Cable \(muscle.displayName)", primary: [muscle], equipment: "cable", style: .weightReps
            )
        }
        store.createProfile(name: "Gym", isActive: true, availableEquipment: ["barbell", "cable"])
    }

    private func request(_ store: WorkoutStore) -> ProgramRequest {
        ProgramRequest(
            goal: .hypertrophy, daysPerWeek: 4, sessionMinutes: 60, experience: .intermediate,
            availableEquipment: store.equipmentKindsForProgram()
        )
    }

    // MARK: - Program generator

    @Test("apply creates one routine per day plus a program with a closing deload; undo removes all of it")
    func programApplyAndUndo() throws {
        let store = try makeStore()
        seedLibrary(store)
        let request = request(store)
        let template = ProgramTemplateEngine.template(for: request)
        let pool = store.programPool(for: template, request: request)
        let draft = try #require(ProgramDefaultPicks.draft(template: template, pool: pool, request: request))
        let routinesBefore = store.routines().count

        let application = try #require(store.applyProgramDraft(draft, template: template, request: request))
        #expect(application.routineIDs.count == 4)
        #expect(store.routines().count == routinesBefore + 4)
        let program = try #require(store.programs().first { $0.id == application.programID })
        #expect(program.routineIDs == application.routineIDs)
        #expect(program.weeks == 4)
        #expect(program.programWeeks.map(\.kind) == [.normal, .normal, .normal, .deload])
        #expect(!program.isActive)
        let (info, drafts) = try #require(store.routineDrafts(id: application.routineIDs[0]))
        #expect(drafts.count == template.days[0].slots.count)
        #expect(drafts[0].sets.count == template.days[0].slots[0].sets)
        #expect(drafts[0].sets[0].targetReps == template.days[0].slots[0].repLow)
        #expect(info.name.hasPrefix(template.days[0].name))

        store.undoProgramApplication(application)
        #expect(store.routines().count == routinesBefore)
        #expect(!store.programs().contains { $0.id == application.programID })
    }

    @Test("a mock model's draft with a foreign exercise is rejected; the default picks still apply")
    func modelDraftRejectedFallsBack() async throws {
        let store = try makeStore()
        seedLibrary(store)
        let request = request(store)
        let template = ProgramTemplateEngine.template(for: request)
        let pool = store.programPool(for: template, request: request)
        let mock = MockCoachModel()
        mock.draftToReturn = ProgramDraft(
            name: "Bad", picks: template.slots.map { ProgramPick(slotID: $0.id, exerciseID: UUID()) }
        )
        await #expect(throws: ProgramDraftError.self) {
            try await mock.draftProgram(template: template, pool: pool, request: request)
        }
        let fallback = try await RuleCoachModel().draftProgram(
            template: template, pool: pool, request: request
        )
        #expect(fallback.picks.count == template.slots.count)
    }

    // MARK: - Review actions

    private func benchRoutine(_ store: WorkoutStore) -> (bench: ExerciseInfo, routine: RoutineInfo) {
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let sets = (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60) }
        let routine = store.saveRoutine(
            id: nil, name: "Push", rule: .linear(incrementKg: 2.5),
            exercises: [RoutineExerciseDraft(exerciseID: bench.id, sets: sets)]
        )
        return (bench, routine)
    }

    @Test("changing a rep range rewrites the planned sets, and undo restores them")
    func repRangeChangeAndUndo() throws {
        let store = try makeStore()
        let (bench, routine) = benchRoutine(store)
        let change = ReviewChange.changeRepRange(exerciseID: bench.id, low: 5, high: 8)
        let applied = try #require(store.applyReviewChange(change))
        #expect(applied.message.contains("5–8"))
        var drafts = try #require(store.routineDrafts(id: routine.id)).drafts
        #expect(drafts[0].sets.map(\.targetReps) == [5, 5, 5])
        #expect(drafts[0].sets.map(\.targetRepsHigh) == [8, 8, 8])
        store.undoReviewChange(applied)
        drafts = try #require(store.routineDrafts(id: routine.id)).drafts
        #expect(drafts[0].sets.map(\.targetReps) == [8, 8, 8])
        #expect(drafts[0].sets.map(\.targetRepsHigh) == [nil, nil, nil])
    }

    @Test("adding, swapping and re-ruling an exercise each edit the routine and undo cleanly")
    func addSwapRuleAndUndo() throws {
        let store = try makeStore()
        let (bench, routine) = benchRoutine(store)
        let fly = store.createCustomExercise(
            name: "Cable Fly", primary: [.chest], equipment: "cable", style: .weightReps
        )

        let added = try #require(store.applyReviewChange(.addExercise(fly.id)))
        #expect(store.routineDrafts(id: routine.id)?.drafts.map(\.exerciseID) == [bench.id, fly.id])
        store.undoReviewChange(added)
        #expect(store.routineDrafts(id: routine.id)?.drafts.map(\.exerciseID) == [bench.id])

        let swapped = try #require(store.applyReviewChange(.swapExercise(from: bench.id, to: fly.id)))
        #expect(store.routineDrafts(id: routine.id)?.drafts.map(\.exerciseID) == [fly.id])
        store.undoReviewChange(swapped)
        #expect(store.routineDrafts(id: routine.id)?.drafts.map(\.exerciseID) == [bench.id])

        let rule = ProgressionRule.doubleProgression(low: 8, high: 12, incrementKg: 2.5)
        let reruled = try #require(
            store.applyReviewChange(.changeProgressionRule(exerciseID: bench.id, rule: rule))
        )
        #expect(store.routineDrafts(id: routine.id)?.drafts[0].overrideRule == rule)
        store.undoReviewChange(reruled)
        #expect(store.routineDrafts(id: routine.id)?.drafts[0].overrideRule == nil)

        // A lift nobody programmes is refused rather than silently "applied".
        #expect(store.applyReviewChange(.deloadLift(UUID())) == nil)
    }

    @Test("moving a rest day rewrites the schedule and undo puts it back")
    func moveRestDayAndUndo() throws {
        let store = try makeStore()
        let (_, routine) = benchRoutine(store)
        store.saveSchedule(WeeklySchedule(days: [.monday: routine.id]))
        let moved = try #require(store.applyReviewChange(.moveRestDay(from: .monday, to: .friday)))
        #expect(store.schedule().days == [.friday: routine.id])
        // Moving onto a day that already has a session is refused.
        #expect(store.applyReviewChange(.moveRestDay(from: .friday, to: .friday)) == nil)
        store.undoReviewChange(moved)
        #expect(store.schedule().days == [.monday: routine.id])
    }

    @Test("the digest lists programmed lifts, adherence and gaps from the same coach input")
    func digestFromStore() throws {
        let store = try makeStore()
        let (bench, routine) = benchRoutine(store)
        store.saveSchedule(WeeklySchedule(days: [.monday: routine.id]))
        let digest = store.trainingDigest()
        #expect(digest.lifts.map(\.id) == [bench.id])
        #expect(digest.lifts[0].repLow == 8)
        #expect(digest.adherencePercent == 0)
        #expect(digest.trainingDays == [.monday])
        #expect(digest.factIDs.contains(TrainingDigest.FactID.lift(0)))
    }

    // MARK: - Questions

    @Test("the tools answer from the store in the lifter's unit, and the rule model grounds on them")
    func toolsAndRuleAnswer() async throws {
        let store = try makeStore()
        let (bench, routine) = benchRoutine(store)
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].weightKg = 80
        session.exercises[0].sets[0].reps = 8
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
        let source = CoachFactsSource(store: store, unit: .kg)

        let last = source.answerCoachQuery(.lastSessions(exercise: "bench press"))
        #expect(last.text.contains("80 kg × 8"))
        #expect(source.answerCoachQuery(.lastSessions(exercise: "Nope")).text.contains("No exercise"))
        #expect(source.answerCoachQuery(.recovery(muscle: "chest")).text.contains("% recovered"))
        #expect(source.answerCoachQuery(.adherence(weeks: 4)).text.contains("No sessions were planned"))
        #expect(source.exerciseNamesForCoach.contains(bench.name))

        let answer = try await RuleCoachModel().answer(question: "what did I bench last time", tools: source)
        #expect(answer.isGrounded)
        #expect(answer.text == last.text)
        #expect(CoachAnswerValidator.isGrounded(answer: answer.text, toolResults: answer.toolResults))
    }

    @Test("the intent speaks a grounded model answer, the tool results when it isn't, rules when it fails")
    func intentAnswerFallbacks() async throws {
        let store = try makeStore()
        _ = benchRoutine(store)
        let source = CoachFactsSource(store: store, unit: .kg)
        let mock = MockCoachModel()
        let tool = CoachToolResult(text: "Last bench: 80 kg × 8")
        let grounded = "You benched 80 kg for 8."
        mock.answerToReturn = CoachAnswer(text: grounded, toolResults: [tool], isGrounded: true)
        #expect(await AskDaGymIntent.answer(question: "bench?", model: mock, source: source) == grounded)

        mock.answerToReturn = CoachAnswer(text: "You benched 85 kg.", toolResults: [tool], isGrounded: false)
        #expect(await AskDaGymIntent.answer(question: "bench?", model: mock, source: source) == tool.text)

        mock.shouldFail = true
        let spoken = await AskDaGymIntent.answer(
            question: "what did I bench last time", model: mock, source: source
        )
        #expect(spoken.contains("No logged sessions of Bench Press"))
    }
}
