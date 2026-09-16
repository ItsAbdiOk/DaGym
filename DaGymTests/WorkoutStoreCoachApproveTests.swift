import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Approving a coach card. The headline behaviour: Approve has to change what the lifter is
/// actually asked to lift next session, and it must not disturb the stall state the progression
/// engine's own deload counts on.
@MainActor
@Suite("WorkoutStore coach: approving a deload")
struct WorkoutStoreCoachApproveTests {
    @discardableResult
    private func benchRoutine(_ store: WorkoutStore, name: String = "Bench Press") -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: name, primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)]
        )
        return store.saveRoutine(
            id: nil, name: name, rule: .linear(incrementKg: 2.5), exercises: [draft]
        )
    }

    private func logMiss(_ store: WorkoutStore, routineID: UUID) {
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].weightKg = 80
        session.exercises[0].sets[0].reps = 6
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
    }

    /// A routine stalled at 80 kg through the real progression path, plus the card it produces.
    ///
    /// Two logged misses, not three. `finish` commits the stall `startWorkout` already computed,
    /// so the persisted counter lags a session: two sessions leave it at 1, which is where the
    /// card fires and where the engine is still prescribing a repeat at 80. A third session takes
    /// it to 2, at which point the engine's own deload is already the next prescription and there
    /// is nothing left for Approve to change.
    private func stalledRoutineAndCard(
        _ store: WorkoutStore
    ) throws -> (routine: RoutineInfo, card: CoachCard) {
        let routine = benchRoutine(store)
        for _ in 0..<2 { logMiss(store, routineID: routine.id) }
        let card = try #require(store.coachCards().first { $0.rule == .stalledLift })
        return (routine, card)
    }

    private func approve(_ store: WorkoutStore, card: CoachCard) throws -> CoachDeloadApplication {
        guard case .deloadExercise(let name, let exerciseID, let toWeightKg) = card.suggestedAction else {
            throw ApproveTestError.notADeloadCard
        }
        return try #require(
            store.applyCoachDeload(exerciseID: exerciseID, exerciseName: name, toWeightKg: toWeightKg)
        )
    }

    private enum ApproveTestError: Error { case notADeloadCard }

    @Test("approving actually changes what the next session prescribes")
    func approveChangesTheNextPrescription() throws {
        let store = try makeStore()
        let (routine, card) = try stalledRoutineAndCard(store)

        // Before: the engine prescribes from history, so it repeats the stalled weight.
        #expect(store.startWorkout(routineID: routine.id).exercises[0].sets[0].weightKg == 80)

        let applied = try approve(store, card: card)
        #expect(applied.weightKg < 80)

        let next = store.startWorkout(routineID: routine.id)
        #expect(next.exercises[0].sets[0].weightKg == applied.weightKg)
        #expect(next.exercises[0].whyTitle == "From your updated plan")
    }

    /// The old implementation reset the streak to 0 and pointed `lastWeightKg` at the new number.
    /// `ProgressionEngine.resetIfWeightChanged` then compared that against the *history* weight,
    /// read a mismatch as "the lifter changed the weight", and zeroed a streak that was two
    /// thirds of the way to the engine's own deload — so approving a deload pushed the real
    /// deload three sessions further away.
    @Test("approving doesn't clobber the stall state the engine's own deload depends on")
    func approveLeavesStallStateAlone() throws {
        let store = try makeStore()
        let (routine, card) = try stalledRoutineAndCard(store)

        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        let routineExercise = try #require(routineModel.exercises?.first)
        let before = routineExercise.stallStateValue
        #expect(before.consecutiveMisses == 1)

        _ = try approve(store, card: card)
        #expect(routineExercise.stallStateValue == before)
    }

    @Test("undo puts the plan and the prescription back exactly as they were")
    func undoRestoresEverything() throws {
        let store = try makeStore()
        let (routine, card) = try stalledRoutineAndCard(store)
        let applied = try approve(store, card: card)

        store.undoCoachDeload(applied)

        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        let routineExercise = try #require(routineModel.exercises?.first)
        #expect(routineExercise.plannedSets?.first?.targetWeightKg == 80)
        #expect(store.startWorkout(routineID: routine.id).exercises[0].sets[0].weightKg == 80)
    }

    @Test("the weight written to the plan is the rounded one the card promised")
    func writtenWeightMatchesTheCard() throws {
        let store = try makeStore()
        let (routine, card) = try stalledRoutineAndCard(store)
        guard case .deloadExercise(_, _, let promised) = card.suggestedAction else {
            Issue.record("expected a deload suggested action")
            return
        }
        let applied = try approve(store, card: card)
        #expect(applied.weightKg == promised)

        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        let routineExercise = try #require(routineModel.exercises?.first)
        #expect(routineExercise.plannedSets?.first?.targetWeightKg == promised)
    }

    @Test("only the working sets' target weight changes — never the set count")
    func setCountIsUntouched() throws {
        let store = try makeStore()
        let (routine, card) = try stalledRoutineAndCard(store)
        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        let routineExercise = try #require(routineModel.exercises?.first)
        let countBefore = routineExercise.plannedSets?.count

        _ = try approve(store, card: card)
        #expect(routineExercise.plannedSets?.count == countBefore)
        #expect(routineExercise.plannedSets?.first?.targetReps == 8)
    }

    @Test("a same-named exercise in another routine is left alone — the match is by id")
    func matchesByIdNotName() throws {
        let store = try makeStore()
        let (_, card) = try stalledRoutineAndCard(store)
        // A second, entirely separate custom exercise that happens to share the name.
        let other = benchRoutine(store, name: "Bench Press")

        _ = try approve(store, card: card)

        let otherModel = try #require(store.fetchRoutineModel(id: other.id))
        let otherExercise = try #require(otherModel.exercises?.first)
        #expect(otherExercise.plannedSets?.first?.targetWeightKg == 80)
    }

    @Test("an archived routine is never rewritten")
    func archivedRoutinesAreSkipped() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        // Two misses: the third is the linear rule's own deload, which drops the weight and
        // zeroes the streak, so the card we want fires on the session before that.
        for _ in 0..<2 { logMiss(store, routineID: routine.id) }
        let card = try #require(store.coachCards().first { $0.rule == .stalledLift })
        guard case .deloadExercise(let name, let exerciseID, let toWeightKg) = card.suggestedAction else {
            Issue.record("expected a deload suggested action")
            return
        }

        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        routineModel.isArchived = true
        store.save()

        let applied = store.applyCoachDeload(
            exerciseID: exerciseID, exerciseName: name, toWeightKg: toWeightKg
        )
        #expect(applied == nil)
        #expect(routineModel.exercises?.first?.plannedSets?.first?.targetWeightKg == 80)
    }

    // MARK: - The override is one-shot

    /// The headline defect. `applyCoachDeload` writes the deloaded weight onto the plan and
    /// stamps `RoutineModel.updatedAt`; `planOverridesPrescription` used to fire on nothing more
    /// than "the routine was saved after the baseline session *and* some working set carries a
    /// target weight" — a condition that, once true, is true for ever. `saveRoutine` stamps
    /// `updatedAt` on every save, a rename included, so a months-old deload weight came back
    /// whenever the lifter touched the routine at all.
    @Test("the approved weight applies to exactly one session, then the engine takes over again")
    func approvedDeloadIsOneShot() throws {
        let store = try makeStore()
        let (routine, card) = try stalledRoutineAndCard(store)
        let applied = try approve(store, card: card)

        // Session 1 after approving: the plan wins, as promised.
        let overridden = store.startWorkout(routineID: routine.id)
        #expect(overridden.exercises[0].sets[0].weightKg == applied.weightKg)
        #expect(overridden.exercises[0].whyTitle == "From your updated plan")
        overridden.exercises[0].sets[0].weightKg = applied.weightKg
        overridden.exercises[0].sets[0].reps = 8
        overridden.exercises[0].sets[0].isDone = true
        _ = store.finish(session: overridden)

        // Session 2: the plan still says the deloaded weight, but it has been used. The engine
        // is back in charge and adds its increment to what was actually logged.
        let next = store.startWorkout(routineID: routine.id)
        #expect(next.exercises[0].whyTitle != "From your updated plan")
        #expect(next.exercises[0].sets[0].weightKg == applied.weightKg + 2.5)
        store.discard(session: next)
    }

    /// Rebuild past the deloaded weight, then rename the routine. The rename bumps `updatedAt`
    /// exactly as a real `saveRoutine` does, and must change nothing.
    @Test("renaming the routine months later never re-applies the deloaded weight")
    func renamingNeverReAppliesTheDeload() throws {
        let store = try makeStore()
        let (routine, card) = try stalledRoutineAndCard(store)
        let applied = try approve(store, card: card)

        // Log the deloaded session, then climb back above where the stall was.
        var weight = applied.weightKg
        for _ in 0..<7 {
            let session = store.startWorkout(routineID: routine.id)
            weight = session.exercises[0].sets[0].weightKg
            session.exercises[0].sets[0].reps = 8
            session.exercises[0].sets[0].isDone = true
            _ = store.finish(session: session)
        }
        #expect(weight > 80, "expected the lifter to have rebuilt past the stall")

        // A rename: `saveRoutine` stamps `updatedAt` on every save, whatever changed.
        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        routineModel.name = "Push A (heavy)"
        routineModel.updatedAt = Date()
        store.save()

        let next = store.startWorkout(routineID: routine.id)
        #expect(next.exercises[0].whyTitle != "From your updated plan")
        #expect(next.exercises[0].sets[0].weightKg > applied.weightKg)
        store.discard(session: next)
    }

    /// The same stamp is shared by every exercise in the routine, so approving a deload on one
    /// lift used to drag every *other* lift in that routine carrying a plan target back to its
    /// plan weight too.
    @Test("approving a deload on one lift leaves the routine's other lifts alone")
    func approvingOneLiftDoesNotRevertTheOthers() throws {
        let store = try makeStore()
        let squat = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let row = store.createCustomExercise(
            name: "Barbell Row", primary: [.lats], equipment: "Barbell", style: .weightReps
        )
        let drafts = [squat, row].map {
            RoutineExerciseDraft(
                exerciseID: $0.id,
                sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)]
            )
        }
        let routine = store.saveRoutine(
            id: nil, name: "Lower", rule: .linear(incrementKg: 2.5), exercises: drafts
        )
        // Two sessions: the squat stalls at 80, the row keeps hitting and climbs.
        for reps in [8, 8] {
            let session = store.startWorkout(routineID: routine.id)
            session.exercises[0].sets[0].weightKg = 80
            session.exercises[0].sets[0].reps = 6
            session.exercises[0].sets[0].isDone = true
            session.exercises[1].sets[0].reps = reps
            session.exercises[1].sets[0].isDone = true
            _ = store.finish(session: session)
        }
        let preview = store.startWorkout(routineID: routine.id)
        let rowWeightBefore = preview.exercises[1].sets[0].weightKg
        store.discard(session: preview)
        #expect(rowWeightBefore > 80)

        let card = try #require(store.coachCards().first {
            $0.rule == .stalledLift && $0.title.contains("Squat")
        })
        _ = try approve(store, card: card)

        let next = store.startWorkout(routineID: routine.id)
        #expect(next.exercises[1].sets[0].weightKg == rowWeightBefore)
        #expect(next.exercises[1].whyTitle != "From your updated plan")
        store.discard(session: next)
    }
}
