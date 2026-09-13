import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Store parity: sessions")
struct ParityStoreSessionsTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeExercise(
        _ store: WorkoutStore, name: String, style: ExerciseInfo.LoggingStyle = .weightReps
    ) -> ExerciseInfo {
        store.createCustomExercise(name: name, primary: [.chest], equipment: "Barbell", style: style)
    }

    /// One routine slot with `setCount` working sets at `targetWeightKg` × `targetReps`.
    private func makeRoutine(
        _ store: WorkoutStore, name: String = "Push A", exerciseID: UUID, setCount: Int = 1,
        targetReps: Int = 5, targetWeightKg: Double? = 80, excludeFromProgression: Bool = false
    ) -> UUID {
        let set = PlannedSetDraft(kind: .working, targetReps: targetReps, targetWeightKg: targetWeightKg)
        let sets = Array(repeating: set, count: setCount)
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID, sets: sets, excludeFromProgression: excludeFromProgression
        )
        return store.saveRoutine(id: nil, name: name, exercises: [draft]).id
    }

    /// Ticks every set at `weightKg` × `reps` (or `durationSeconds`) and finishes.
    @discardableResult
    private func logSession(
        _ store: WorkoutStore, routineID: UUID, weightKg: Double, reps: Int, durationSeconds: Int? = nil,
        doneCount: Int? = nil, wasPlannedDeload: Bool = false
    ) -> WorkoutSession {
        let session = store.startWorkout(routineID: routineID)
        for index in session.exercises[0].sets.indices {
            session.exercises[0].sets[index].weightKg = weightKg
            session.exercises[0].sets[index].reps = reps
            session.exercises[0].sets[index].durationSeconds = durationSeconds
            session.exercises[0].sets[index].isDone = index < (doneCount ?? Int.max)
        }
        session.exercises[0].wasPlannedDeload = wasPlannedDeload
        _ = store.finish(session: session)
        return session
    }

    // MARK: - Rec 1: previous session skips deloads and empty sessions

    @Test("a planned deload is not the previous session — the one before it is")
    func previousSkipsPlannedDeload() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let routineID = makeRoutine(store, exerciseID: bench.id, setCount: 3)
        logSession(store, routineID: routineID, weightKg: 80, reps: 5)
        logSession(store, routineID: routineID, weightKg: 72, reps: 5, wasPlannedDeload: true)

        let next = store.startWorkout(routineID: routineID)
        #expect(next.exercises[0].sets[0].previousWeightKg == 80)
        #expect(next.exercises[0].sets[0].previousReps == 5)
        #expect(next.exercises[0].sets[0].weightKg == 80)
        store.discard(session: next)
    }

    @Test("a session with nothing completed is skipped for the one before it")
    func previousSkipsEmptySession() throws {
        let store = try makeStore()
        let rows = makeExercise(store, name: "Barbell Row")
        let routineID = makeRoutine(
            store, exerciseID: rows.id, setCount: 3, targetReps: 10, targetWeightKg: 50
        )
        logSession(store, routineID: routineID, weightKg: 60, reps: 10)
        logSession(store, routineID: routineID, weightKg: 0, reps: 0, doneCount: 0)

        let next = store.startWorkout(routineID: routineID)
        #expect(next.exercises[0].sets[0].weightKg == 60)
        #expect(next.exercises[0].sets[0].previousReps == 10)
        #expect(next.exercises[0].lastSessions.first == "60 × 10,10,10")
        store.discard(session: next)
    }

    @Test("an exercise only ever logged in a deload falls through to the plan target, no ghost")
    func onlyDeloadHistoryUsesPlan() throws {
        let store = try makeStore()
        let curl = makeExercise(store, name: "Curl")
        let routineID = makeRoutine(store, exerciseID: curl.id, targetReps: 12, targetWeightKg: 12)
        logSession(store, routineID: routineID, weightKg: 10, reps: 12, wasPlannedDeload: true)

        let next = store.startWorkout(routineID: routineID)
        #expect(next.exercises[0].sets[0].weightKg == 12)
        #expect(next.exercises[0].sets[0].previousWeightKg == nil)
        store.discard(session: next)
    }

    // MARK: - Rec 2: excluded routine slots never become the baseline

    @Test("a rehab session under an excluded slot is not the ghost or the engine baseline")
    func excludedSessionIsNotBaseline() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let ppl = makeRoutine(store, name: "Push A", exerciseID: bench.id)
        let rehab = makeRoutine(
            store, name: "Rehab", exerciseID: bench.id, targetReps: 15, targetWeightKg: 40,
            excludeFromProgression: true
        )
        logSession(store, routineID: ppl, weightKg: 80, reps: 5)
        logSession(store, routineID: rehab, weightKg: 40, reps: 15)

        let next = store.startWorkout(routineID: ppl)
        #expect(next.exercises[0].sets[0].previousWeightKg == 80)
        #expect(next.exercises[0].sets[0].previousReps == 5)
        #expect(store.exerciseHistory(exerciseID: bench.id).first?.sets.first?.weightKg == 80)
        store.discard(session: next)
    }

    @Test("editing the routine flag later never changes an already-saved workout")
    func excludedFlagIsStampedAtBuildTime() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let rehab = makeRoutine(
            store, name: "Rehab", exerciseID: bench.id, targetReps: 15, targetWeightKg: 40,
            excludeFromProgression: true
        )
        let session = logSession(store, routineID: rehab, weightKg: 40, reps: 15)
        let workoutID = try #require(session.workoutID)
        #expect(store.workout(id: workoutID)?.exercises?.first?.excludedFromProgression == true)

        let drafts = try #require(store.routineDrafts(id: rehab)).drafts.map { draft in
            var draft = draft
            draft.excludeFromProgression = false
            return draft
        }
        store.saveRoutine(id: rehab, name: "Rehab", exercises: drafts)
        #expect(store.workout(id: workoutID)?.exercises?.first?.excludedFromProgression == true)
        #expect(store.exerciseHistory(exerciseID: bench.id).isEmpty)
    }

    // MARK: - Rec 3: finish keeps only what was done

    @Test("finishing drops unticked rows: 4 planned, 3 done → history lists 3")
    func finishDropsUndoneSets() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let routineID = makeRoutine(store, exerciseID: bench.id, setCount: 4)
        let session = logSession(store, routineID: routineID, weightKg: 80, reps: 5, doneCount: 3)
        let workoutID = try #require(session.workoutID)

        let detail = store.workoutDetail(id: workoutID)
        #expect(detail.exercises.first?.sets.count == 3)
        let benchModel = try #require(store.fetchExerciseModel(id: bench.id))
        #expect(store.exerciseInfo(for: benchModel).sessions == 1)
    }

    @Test("an exercise added then left untouched is not in history and doesn't count a session")
    func finishDropsUntouchedExercise() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let curl = makeExercise(store, name: "Curl")
        let routineID = makeRoutine(store, exerciseID: bench.id)
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        session.exercises.append(store.autoFilledEntry(for: curl))
        _ = store.finish(session: session)
        let workoutID = try #require(session.workoutID)

        let detail = store.workoutDetail(id: workoutID)
        #expect(detail.exercises.map(\.exercise.id) == [bench.id])
        let curlModel = try #require(store.fetchExerciseModel(id: curl.id))
        #expect(store.exerciseInfo(for: curlModel).sessions == 0)
    }

    @Test("a backfill with nothing ticked on one exercise keeps the others and drops that one")
    func backfillDropsEmptyExercise() throws {
        let store = try makeStore()
        let bench = makeExercise(store, name: "Bench Press")
        let curl = makeExercise(store, name: "Curl")
        let drafts = [bench, curl].map {
            RoutineExerciseDraft(
                exerciseID: $0.id, sets: [PlannedSetDraft(targetReps: 8, targetWeightKg: 40)]
            )
        }
        let routineID = store.saveRoutine(id: nil, name: "Both", exercises: drafts).id
        let date = Date().addingTimeInterval(-86_400)
        let session = store.startBackfill(date: date, durationMinutes: 45, routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
        let workoutID = try #require(session.workoutID)

        let detail = store.workoutDetail(id: workoutID)
        #expect(detail.exercises.map(\.exercise.id) == [bench.id])
        #expect(store.history().count == 1)
    }

    // MARK: - Rec 8: history line and sparkline follow the logging style

    @Test("a timed hold's line is its holds as clocks and its sparkline the best hold")
    func timedHoldLineAndSparkline() throws {
        let store = try makeStore()
        let plank = makeExercise(store, name: "Plank", style: .timedHold)
        let routineID = makeRoutine(
            store, exerciseID: plank.id, setCount: 3, targetReps: 0, targetWeightKg: 0
        )
        logSession(store, routineID: routineID, weightKg: 0, reps: 0, durationSeconds: 45)
        logSession(store, routineID: routineID, weightKg: 0, reps: 0, durationSeconds: 40)
        let last = store.startWorkout(routineID: routineID)
        for (index, seconds) in [45, 40, 38].enumerated() {
            last.exercises[0].sets[index].durationSeconds = seconds
            last.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: last)

        #expect(store.lastSessions(exerciseID: plank.id).first == "0:45, 0:40, 0:38")
        #expect(store.sparklineSeries(exerciseID: plank.id).map(\.1) == [45, 40, 45])
    }

    @Test("bodyweight reps read as a reps list with a best-reps sparkline; loaded lifts unchanged")
    func bodyweightAndLoadedLines() throws {
        let store = try makeStore()
        let pushUps = makeExercise(store, name: "Push-Up", style: .bodyweightReps)
        let pushRoutine = makeRoutine(
            store, exerciseID: pushUps.id, setCount: 3, targetReps: 12, targetWeightKg: 0
        )
        let session = store.startWorkout(routineID: pushRoutine)
        for (index, reps) in [12, 12, 10].enumerated() {
            session.exercises[0].sets[index].reps = reps
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)
        #expect(store.lastSessions(exerciseID: pushUps.id).first == "12, 12, 10")
        #expect(store.sparklineSeries(exerciseID: pushUps.id).map(\.1) == [12])

        let bench = makeExercise(store, name: "Bench Press")
        let benchRoutine = makeRoutine(store, exerciseID: bench.id, setCount: 3)
        logSession(store, routineID: benchRoutine, weightKg: 80, reps: 5)
        #expect(store.lastSessions(exerciseID: bench.id).first == "80 × 5,5,5")
        let e1rm = store.e1rmSeries(exerciseID: bench.id).map(\.1)
        #expect(store.sparklineSeries(exerciseID: bench.id).map(\.1) == e1rm)
    }

    // MARK: - Rec 10: added exercise mirrors the last session's set count

    @Test("autoFilledEntry has as many rows as the last session did working sets, else 3")
    func autoFilledEntrySetCount() throws {
        let store = try makeStore()
        let rows = makeExercise(store, name: "Barbell Row")
        let routineID = makeRoutine(
            store, exerciseID: rows.id, setCount: 5, targetReps: 10, targetWeightKg: 60
        )
        logSession(store, routineID: routineID, weightKg: 60, reps: 10)
        #expect(store.autoFilledEntry(for: rows).sets.count == 5)
        #expect(store.autoFilledEntry(for: rows, setCount: 2).sets.count == 2)

        let never = makeExercise(store, name: "Never Logged")
        #expect(store.autoFilledEntry(for: never).sets.count == 3)
    }

    // MARK: - Rec 11: a deload's baseline skips the previous deload

    @Test("two consecutive planned deload weeks both take 90% of the last normal load")
    func consecutiveDeloadsShareBaseline() throws {
        let store = try makeStore()
        let squat = makeExercise(store, name: "Squat")
        let routineID = makeRoutine(store, exerciseID: squat.id, targetWeightKg: 100)
        logSession(store, routineID: routineID, weightKg: 100, reps: 5)

        let program = ProgramModel(name: "Deload", weeks: 1, startedAt: Date(), isActive: true)
        program.routineIDs = [routineID]
        store.context.insert(program)
        let week = ProgramWeekModel(index: 1, kind: ProgramWeekKind.deload.rawValue, program: program)
        store.context.insert(week)
        program.programWeeks = [week]
        store.save()

        let first = store.startWorkout(routineID: routineID)
        #expect(first.exercises[0].wasPlannedDeload)
        #expect(first.exercises[0].sets[0].weightKg == 90)
        first.exercises[0].sets[0].isDone = true
        _ = store.finish(session: first)

        let second = store.startWorkout(routineID: routineID)
        #expect(second.exercises[0].sets[0].weightKg == 90)
        store.discard(session: second)
    }
}
