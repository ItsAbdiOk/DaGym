import Foundation
import GymCore
import Testing

@testable import DaGym

/// Superset round rest, re-ticked sets, unit reorder, logged-set swaps and drop-set seeding —
/// the session-side half of docs/reviews/opengym/sessions.md.
@MainActor
@Suite("WorkoutSession parity")
struct ParityWorkoutSessionTests {
    private func exercise(
        _ name: String, primary: Muscle = .chest, rest: Int = 150, increment: Double = 2.5
    ) -> ExerciseInfo {
        ExerciseInfo(
            name: name, primary: [primary], equipment: "Barbell", incrementKg: increment, restSeconds: rest
        )
    }

    private func entry(
        _ exercise: ExerciseInfo, weightKg: Double = 80, sets: Int = 3, done: Int = 0, group: Int? = nil
    ) -> WorkoutExerciseEntry {
        let rows = (0..<sets).map { SetEntry(weightKg: weightKg, reps: 5, isDone: $0 < done) }
        return WorkoutExerciseEntry(exercise: exercise, sets: rows, supersetGroup: group)
    }

    private func session(_ exercises: [WorkoutExerciseEntry]) -> WorkoutSession {
        let session = WorkoutSession(title: "Push", subtitle: "", startedAt: Date(), exercises: exercises)
        session.restHaptics = false
        return session
    }

    private func complete(_ session: WorkoutSession, exercise ei: Int, set si: Int) {
        session.completeSet(exerciseID: session.exercises[ei].id, setID: session.exercises[ei].sets[si].id)
    }

    // MARK: Rec 5 — superset round rest

    @Test("a superset rests once per round, using the longest rest in the group")
    func supersetRoundRest() {
        let bench = exercise("Bench Press", rest: 150)
        let row = exercise("Barbell Row", primary: .lats, rest: 90)
        let session = session([entry(bench, group: 1), entry(row, weightKg: 60, group: 1)])

        complete(session, exercise: 0, set: 0)
        #expect(session.restRemaining == 0)
        #expect(session.restNextLabel == "Next Barbell Row")

        complete(session, exercise: 1, set: 0)
        #expect(session.restRemaining == 150)
        #expect(session.restNextLabel.isEmpty)
        #expect(session.restNextWeightKg == 80)
        #expect(session.restNextReps == 5)
    }

    @Test("a partner that has finished all its sets is skipped, and the round still rests")
    func spentPartnerIsSkipped() {
        let bench = exercise("Bench Press", rest: 150)
        let row = exercise("Barbell Row", primary: .lats, rest: 90)
        let curl = exercise("Curl", primary: .biceps, rest: 60)
        let session = session([
            entry(bench, sets: 3, done: 2, group: 1), entry(row, sets: 2, done: 2, group: 1), entry(curl)
        ])

        complete(session, exercise: 0, set: 2)
        #expect(session.restRemaining == 150)
        #expect(session.restNextLabel == "Next Curl")
    }

    @Test("a singleton keeps its own rest and next-set preview")
    func singletonUnchanged() {
        let session = session([entry(exercise("Bench Press", rest: 120))])
        complete(session, exercise: 0, set: 0)
        #expect(session.restRemaining == 120)
        #expect(session.restNextWeightKg == 80)
    }

    @Test("the session's last set starts no timer and reads Last set done")
    func lastSetOfSession() {
        let session = session([entry(exercise("Bench Press"), sets: 2, done: 1)])
        complete(session, exercise: 0, set: 1)
        #expect(session.restRemaining == 0)
        #expect(!session.isResting)
        #expect(session.restNextLabel == "Last set done")
    }

    // MARK: Rec 6 — re-ticking a set

    @Test("un-ticking and re-ticking a set keeps the running rest")
    func recheckKeepsRunningRest() {
        let session = session([entry(exercise("Bench Press", rest: 150))])
        var clock = Date()
        session.now = { clock }
        let setID = session.exercises[0].sets[1].id
        let exerciseID = session.exercises[0].id
        complete(session, exercise: 0, set: 0)
        complete(session, exercise: 0, set: 1)
        clock = clock.addingTimeInterval(60)
        session.tickRest()
        #expect(session.restRemaining == 90)

        session.uncompleteSet(exerciseID: exerciseID, setID: setID)
        session.exercises[0].sets[1].reps = 4
        session.completeSet(exerciseID: exerciseID, setID: setID)
        #expect(session.restRemaining == 90)
        #expect(session.exercises[0].sets[1].isDone)
    }

    @Test("re-ticking after the rest has expired starts a fresh timer")
    func recheckAfterExpiryRestartsRest() {
        let session = session([entry(exercise("Bench Press", rest: 150))])
        var clock = Date()
        session.now = { clock }
        let setID = session.exercises[0].sets[0].id
        let exerciseID = session.exercises[0].id
        complete(session, exercise: 0, set: 0)
        clock = clock.addingTimeInterval(200)
        session.tickRest()
        #expect(session.restRemaining == 0)

        session.uncompleteSet(exerciseID: exerciseID, setID: setID)
        session.completeSet(exerciseID: exerciseID, setID: setID)
        #expect(session.restRemaining == 150)
    }

    // MARK: Rec 7 — reorder by unit

    @Test("moving a superset moves both members and keeps their group")
    func moveGroupAsUnit() {
        let group1 = entry(exercise("B"), group: 1)
        let group2 = entry(exercise("C"), group: 1)
        let session = session([entry(exercise("A")), group1, group2, entry(exercise("D"))])
        #expect(session.groupedIndices == [[0], [1, 2], [3]])

        session.moveUnits(fromOffsets: [1], toOffset: 0)
        #expect(session.exercises.map(\.exercise.name) == ["B", "C", "A", "D"])
        #expect(session.exercises.map(\.supersetGroup) == [1, 1, nil, nil])
    }

    @Test("moving a singleton above a superset leaves the group intact")
    func moveSingletonAboveGroup() {
        let session = session([
            entry(exercise("A")), entry(exercise("B"), group: 1), entry(exercise("C"), group: 1),
            entry(exercise("D"))
        ])
        session.moveUnits(fromOffsets: [2], toOffset: 1)
        #expect(session.exercises.map(\.exercise.name) == ["A", "D", "B", "C"])
        #expect(session.groupedIndices == [[0], [1], [2, 3]])
    }

    // MARK: Rec 4 — swap after logged sets

    @Test("a swap with logged sets keeps the entry and appends the substitute after it")
    func swapKeepsLoggedSets() {
        let bench = entry(exercise("Bench Press"), sets: 3, done: 2)
        let session = session([bench, entry(exercise("Curl", primary: .biceps))])
        let dumbbell = entry(exercise("Dumbbell Press"), weightKg: 30)

        #expect(session.hasLoggedSets(entryID: bench.id))
        session.insertSubstitute(dumbbell, after: bench.id, keepInSuperset: false)

        #expect(session.exercises.map(\.exercise.name) == ["Bench Press", "Dumbbell Press", "Curl"])
        #expect(session.exercises[0].doneCount == 2)
        #expect(session.exercises[0].sets.count == 3)
        #expect(session.exercises[1].wasSubstitution)
        #expect(session.exercises[1].sets.count == 3)
        #expect(!session.exercises[0].wasSubstitution)
    }

    @Test("a swap with nothing logged replaces in place")
    func swapWithoutLoggedSetsReplaces() {
        let bench = entry(exercise("Bench Press"))
        let session = session([bench])
        #expect(!session.hasLoggedSets(entryID: bench.id))
        session.replaceInPlace(entryID: bench.id, with: exercise("Dumbbell Press"))
        #expect(session.exercises.count == 1)
        #expect(session.exercises[0].exercise.name == "Dumbbell Press")
        #expect(session.exercises[0].wasSubstitution)
    }

    @Test("keeping the substitute in the superset puts it right after the entry with its group")
    func swapKeepInSuperset() {
        let bench = entry(exercise("Bench Press"), done: 1, group: 1)
        let session = session([bench, entry(exercise("Barbell Row", primary: .lats), group: 1)])
        session.insertSubstitute(entry(exercise("Dumbbell Press")), after: bench.id, keepInSuperset: true)
        #expect(session.exercises.map(\.exercise.name) == ["Bench Press", "Dumbbell Press", "Barbell Row"])
        #expect(session.exercises[1].supersetGroup == 1)
        #expect(session.groupedIndices == [[0, 1, 2]])
    }

    @Test("detaching the substitute puts it after the group's last member, ungrouped")
    func swapDetachFromSuperset() {
        let bench = entry(exercise("Bench Press"), done: 1, group: 1)
        let session = session([bench, entry(exercise("Barbell Row", primary: .lats), group: 1)])
        session.insertSubstitute(entry(exercise("Dumbbell Press")), after: bench.id, keepInSuperset: false)
        #expect(session.exercises.map(\.exercise.name) == ["Bench Press", "Barbell Row", "Dumbbell Press"])
        #expect(session.exercises[2].supersetGroup == nil)
        #expect(session.groupedIndices == [[0, 1], [2]])
    }

    // MARK: Rec 9 — drop-set seeding

    @Test("a drop set seeds 80 % of the last row snapped down to the increment")
    func dropSetSeedsEightyPercent() {
        let bench = entry(exercise("Bench Press", increment: 2.5), weightKg: 100)
        let dumbbell = entry(exercise("Dumbbell Curl", primary: .biceps, increment: 2), weightKg: 22)
        let session = session([bench, dumbbell])

        session.addSet(exerciseID: bench.id, kind: .drop)
        session.addSet(exerciseID: dumbbell.id, kind: .drop)
        session.addSet(exerciseID: bench.id, kind: .working)

        let benchSets = session.exercises[0].sets
        #expect(benchSets[3].kind == .drop && benchSets[3].weightKg == 80 && benchSets[3].reps == 5)
        #expect(benchSets[4].kind == .working && benchSets[4].weightKg == 80)
        let curlSets = session.exercises[1].sets
        #expect(curlSets[3].kind == .drop && curlSets[3].weightKg == 16)
        #expect(WorkoutSession.dropWeightKg(from: 100, increment: 2.5) == 80)
    }
}
