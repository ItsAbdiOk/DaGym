import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The adapter's own derivation from real store data. Everything in `GymCoreTests/Coach` feeds
/// hand-built `CoachInput`s, which is exactly why a rule that could never fire from real data,
/// and a counter that flagged perfectly good training, both passed their suites for a week.
@MainActor
@Suite("WorkoutStore coach adapter")
struct WorkoutStoreCoachTests {
    /// A one-exercise linear routine at 80 kg × 8.
    @discardableResult
    private func benchRoutine(
        _ store: WorkoutStore, name: String = "Bench Press", targetReps: Int? = 8,
        targetRepsHigh: Int? = nil, targetSeconds: Int? = nil
    ) -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: name, primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let workingSet = PlannedSetDraft(
            kind: .working, targetReps: targetReps, targetRepsHigh: targetRepsHigh,
            targetWeightKg: 80, targetSeconds: targetSeconds
        )
        let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: [workingSet])
        return store.saveRoutine(
            id: nil, name: name, rule: .linear(incrementKg: 2.5), exercises: [draft]
        )
    }

    /// Logs one real session through `startWorkout`/`finish`, so the progression engine's own
    /// `persistProgression` writes the stall state rather than a test setting it by hand.
    private func logSession(
        _ store: WorkoutStore, routineID: UUID, weightKg: Double = 80, reps: Int = 6,
        kind: SetKind = .working
    ) {
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].kind = kind
        session.exercises[0].sets[0].weightKg = weightKg
        session.exercises[0].sets[0].reps = reps
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
    }

    private func stallState(_ store: WorkoutStore, routineID: UUID) throws -> StallState {
        let routineModel = try #require(store.fetchRoutineModel(id: routineID))
        return try #require(routineModel.exercises?.first).stallStateValue
    }

    // MARK: - The stalled-lift rule against the real progression path

    /// The real sequence, which is not the obvious one. `finish` commits the stall that
    /// `startWorkout` already computed for the session being finished, so the persisted counter
    /// is always one session behind: after N logged misses, N-1 of them have been judged.
    /// `linearMissesBeforeDeload` is 3, so the persisted value only ever reaches 2. The coach
    /// does not read this lagged copy — `coachInput` re-judges each lift over current history,
    /// so its `consecutiveMisses` is the true number of logged misses, and
    /// `coachStalledLiftMisses` (2) means "two real misses, engine still offering a repeat".
    @Test("the persisted miss counter lags a session, and tops out at 2 before the engine deloads")
    func stallCounterFollowsTheRealProgressionPath() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)

        logSession(store, routineID: routine.id) // no history yet: first time, nothing judged
        #expect(try stallState(store, routineID: routine.id).consecutiveMisses == 0)
        logSession(store, routineID: routine.id) // judges session 1
        #expect(try stallState(store, routineID: routine.id).consecutiveMisses == 1)
        logSession(store, routineID: routine.id) // judges session 2
        #expect(try stallState(store, routineID: routine.id).consecutiveMisses == 2)

        // Session 4's prescription judges session 3 — the third real miss — so the engine
        // deloads itself here and zeroes the streak. The counter never reaches 3.
        logSession(store, routineID: routine.id)
        #expect(try stallState(store, routineID: routine.id).consecutiveMisses == 0)
    }

    @Test("the card fires after two real missed sessions, before the engine's own deload")
    func stalledLiftFiresBeforeTheEngineDeloads() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)

        logSession(store, routineID: routine.id)
        #expect(!store.coachCards().contains { $0.rule == .stalledLift })

        logSession(store, routineID: routine.id)
        let card = try #require(store.coachCards().first { $0.rule == .stalledLift })
        // It reports the two sessions that really happened, not the persisted 1.
        #expect(card.body.contains("2 sessions in a row"))
        // And the engine is still offering a repeat at this point, so the card is genuinely
        // early rather than restating a deload the app has already decided on.
        let next = store.startWorkout(routineID: routine.id)
        #expect(next.exercises[0].sets[0].weightKg == 80)
    }

    @Test("the card's deload weight is a load the lifter can actually put on the bar")
    func deloadWeightIsPlateable() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        for _ in 0..<2 { logSession(store, routineID: routine.id, weightKg: 82.5) }

        let card = try #require(store.coachCards().first { $0.rule == .stalledLift })
        guard case .deloadExercise(_, _, let toWeightKg) = card.suggestedAction else {
            Issue.record("expected a deload suggested action")
            return
        }
        // Not 82.5 × 0.9 = 74.25 kg, which is not a number any plate set makes.
        #expect(toWeightKg < 82.5)
        #expect((toWeightKg / 1.25).rounded() * 1.25 == toWeightKg)
    }

    // MARK: - `consecutiveFailedSessions`

    @Test("a to-failure set is a technique, not a failed session")
    func failureKindIsNotAFailedSession() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        for _ in 0..<4 { logSession(store, routineID: routine.id, reps: 10, kind: .failure) }

        let lift = try #require(store.coachInput().lifts.first { $0.name == "Bench Press" })
        #expect(lift.consecutiveFailedSessions == 0)
        #expect(!store.coachCards().contains { $0.rule == .strugglingExercise })
    }

    @Test("a timed hold, which logs no reps, is never short of a rep target")
    func timedHoldIsNotJudgedOnReps() throws {
        let store = try makeStore()
        let routine = benchRoutine(store, name: "Plank", targetReps: nil, targetSeconds: 60)
        for _ in 0..<4 { logSession(store, routineID: routine.id, weightKg: 0, reps: 0) }

        let lift = try #require(store.coachInput().lifts.first { $0.name == "Plank" })
        #expect(lift.consecutiveFailedSessions == 0)
    }

    @Test("hitting the bottom of a rep range is hitting the target, not missing it")
    func repRangeLowEndCounts() throws {
        let store = try makeStore()
        let routine = benchRoutine(store, targetReps: 8, targetRepsHigh: 12)
        for _ in 0..<4 { logSession(store, routineID: routine.id, reps: 8) }

        let lift = try #require(store.coachInput().lifts.first { $0.name == "Bench Press" })
        #expect(lift.consecutiveFailedSessions == 0)
    }

    @Test("genuinely coming up short session after session does count")
    func shortOfTargetCounts() throws {
        let store = try makeStore()
        let routine = benchRoutine(store, targetReps: 8)
        for _ in 0..<4 { logSession(store, routineID: routine.id, reps: 5) }

        let lift = try #require(store.coachInput().lifts.first { $0.name == "Bench Press" })
        #expect(lift.consecutiveFailedSessions == 4)
    }

    // MARK: - Trend length, tracked muscles, drift input

    @Test("the e1RM trend handed to the rules is the window they're specified over")
    func e1rmTrendMatchesItsContract() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        for index in 0..<10 { logSession(store, routineID: routine.id, weightKg: 60 + Double(index)) }

        let lift = try #require(store.coachInput().lifts.first { $0.name == "Bench Press" })
        // 10 logged sessions, but the rules are specified over a 4-session window — and
        // `DeloadDetector.isNotProgressing` compares the array's *first* point against its last,
        // so a 16-long array read "you were stronger months ago" as "not progressing".
        #expect(lift.e1rmTrend.count == TrainingConstants.coachE1rmDowntrendSessions)
    }

    @Test("a muscle that only ever gets secondary work is not a coverage gap")
    func secondaryOnlyMusclesAreNotTracked() throws {
        let store = try makeStore()
        benchRoutine(store)
        // Only the muscles the plan trains directly. A secondary mover counts 0.5 sets in
        // `BodySeries.setsPerMuscle`, so one that only ever gets incidental work could never
        // clear the 4-set floor and would report a gap forever.
        #expect(store.coachInput().trackedMuscles == [.chest])
    }

    @Test("a freestyle session reports no planned sets, so it can't be a drift baseline")
    func freestyleSessionsCarryNoSetSignal() throws {
        let store = try makeStore()
        benchRoutine(store)
        let session = store.startFreestyle()
        _ = store.finish(session: session)

        let summary = try #require(store.coachInput().recentSessions.first)
        #expect(summary.plannedSetCount == 0)
    }

    // MARK: - Purity, dismissal, empty state

    @Test("the same store, `now` and calendar always produce the same cards")
    func adapterIsPureOverNowAndCalendar() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        for _ in 0..<2 { logSession(store, routineID: routine.id) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = store.coachCards(now: now, calendar: calendar)
        let second = store.coachCards(now: now, calendar: calendar)
        #expect(first == second)
    }

    @Test("coachInput reflects the store's own schedule, history and lifts")
    func coachInputReflectsStoreContents() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        logSession(store, routineID: routine.id)

        let input = store.coachInput()
        #expect(input.workoutDates.count == 1)
        #expect(input.lastWorkoutDate != nil)
        let lift = try #require(input.lifts.first { $0.name == "Bench Press" })
        #expect(lift.exerciseID != nil)
        #expect(lift.lastWorkingWeightKg == 80)
    }

    @Test("an empty store produces no cards — the Coach tab's empty state")
    func emptyStoreProducesNoCards() throws {
        let store = try makeStore()
        #expect(store.coachCards().isEmpty)
    }

    @Test("dismissing a card suppresses it within its cooldown and it returns after")
    func dismissalSuppressesWithinCooldownAndReturnsAfterward() throws {
        let store = try makeStore()
        let routine = benchRoutine(store)
        for _ in 0..<2 { logSession(store, routineID: routine.id) }

        let now = Date()
        let stalled = try #require(store.coachCards(now: now).first { $0.rule == .stalledLift })

        store.recordCoachInteraction(
            rule: stalled.rule, fingerprint: stalled.fingerprint, outcome: .dismissed, date: now
        )
        #expect(!store.coachCards(now: now).contains { $0.fingerprint == stalled.fingerprint })

        // Re-fetching interactions from a fresh in-memory read must still suppress it — this is
        // what makes the dismissal survive relaunch, not just this run's in-memory state.
        let reread = store.coachInteractions()
        #expect(reread.contains { $0.fingerprint == stalled.fingerprint && $0.outcome == .dismissed })

        let cooldownDays = CoachRule.stalledLift.cooldownDays
        let afterCooldown = try #require(
            Calendar.current.date(byAdding: .day, value: cooldownDays + 1, to: now)
        )
        #expect(store.coachCards(now: afterCooldown).contains { $0.fingerprint == stalled.fingerprint })
    }

    // MARK: - "RPE at the same load" has to be at the same load

    /// The rule fires when RPE rises a full point across the window. Reading the first working
    /// set's RPE from the last sessions regardless of weight meant a lifter adding weight every
    /// session — where RPE is *supposed* to climb — was told to deload for progressing.
    @Test("RPE rising as the bar goes up is not a rise at the same load")
    func rpeTrendIgnoresSessionsAtADifferentLoad() throws {
        let store = try makeStore()
        let routineID = try rpeRoutine(store)
        for (weightKg, rpe) in [(100.0, 7.0), (102.5, 8.0), (105.0, 8.5)] {
            logRPESession(store, routineID: routineID, weightKg: weightKg, rpe: rpe)
        }

        let snapshot = try #require(
            store.coachLiftSnapshots(finishedWorkouts: store.finishedWorkoutModelsNewestFirst()).first
        )
        #expect(snapshot.rpeAtSameLoadTrend == nil)
        #expect(store.deloadSuggestion(snoozedUntil: nil)?.reason.contains("RPE") != true)
    }

    @Test("RPE rising while the load stays put is still reported")
    func rpeTrendKeepsSessionsAtTheSameLoad() throws {
        let store = try makeStore()
        let routineID = try rpeRoutine(store)
        for rpe in [7.0, 8.0, 8.5] {
            logRPESession(store, routineID: routineID, weightKg: 100, rpe: rpe)
        }

        let snapshot = try #require(
            store.coachLiftSnapshots(finishedWorkouts: store.finishedWorkoutModelsNewestFirst()).first
        )
        #expect(snapshot.rpeAtSameLoadTrend == [7.0, 8.0, 8.5])
    }

    private func rpeRoutine(_ store: WorkoutStore) throws -> UUID {
        let exercise = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 100)]
        )
        return store.saveRoutine(
            id: nil, name: "Lower", rule: .linear(incrementKg: 2.5), exercises: [draft]
        ).id
    }

    private func logRPESession(_ store: WorkoutStore, routineID: UUID, weightKg: Double, rpe: Double) {
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].weightKg = weightKg
        session.exercises[0].sets[0].reps = 5
        session.exercises[0].sets[0].effort = Effort(rpe: rpe)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
    }
}
