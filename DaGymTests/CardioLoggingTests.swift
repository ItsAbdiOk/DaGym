import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Cardio logging end to end (plan.md §6.1): the row the on-deck card lays out, the store's
/// mapping of time / distance / incline both ways, the pre-fill from last session, the backup
/// and plan-share codecs, the routine builder's planned cardio set, the distance unit
/// preference and the voice context. Expected pace numbers are hand-derived: 5 km in 25:30 is
/// 306 s/km = 5:06 and 11.8 km/h.
@MainActor
@Suite("Cardio logging")
struct CardioLoggingTests {
    private func makeStore() throws -> (store: WorkoutStore, context: ModelContext) {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        return (WorkoutStore(context: context), context)
    }

    private func treadmill(_ store: WorkoutStore) -> ExerciseInfo {
        store.createCustomExercise(
            name: "Treadmill Run", primary: [.quads], equipment: "treadmill", style: .cardio
        )
    }

    /// One routine with a single planned cardio set: 20:00 and 5 km.
    private func cardioRoutine(_ store: WorkoutStore, exercise: ExerciseInfo) -> RoutineInfo {
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetSeconds: 1200, targetDistanceMeters: 5000)]
        )
        return store.saveRoutine(id: nil, name: "Run day", exercises: [draft])
    }

    // MARK: - Row layout and pace

    @Test("a cardio entry lays out cardio rows, never weight × reps or hold rows")
    func onDeckRowsAreCardio() {
        let run = ExerciseInfo(name: "Row", primary: [.lats], equipment: "rower", loggingStyle: .cardio)
        let sets = [SetEntry(weightKg: 0, reps: 0, targetSeconds: 600)]
        let entry = WorkoutExerciseEntry(exercise: run, sets: sets)
        #expect(entry.isCardio)
        #expect(entry.onDeckRows == .cardio(startSetID: entry.sets[0].id))
        #expect(!entry.showsInclineByDefault)
        let treadmill = ExerciseInfo(
            name: "Run", primary: [.quads], equipment: "Treadmill", loggingStyle: .cardio
        )
        #expect(WorkoutExerciseEntry(exercise: treadmill, sets: []).showsInclineByDefault)
    }

    @Test("the row's pace line reads 5:06 /km · 11.8 km/h, and is absent until both numbers exist")
    func rowPaceLine() {
        let done = SetEntry(weightKg: 0, reps: 0, durationSeconds: 1530, distanceMeters: 5000)
        #expect(CardioSetRow.paceLine(setEntry: done, unit: .km) == "5:06 /km · 11.8 km/h")
        #expect(CardioSetRow.paceLine(setEntry: done, unit: .mi) == "8:12 /mi · 7.3 mi/h")
        let planned = SetEntry(weightKg: 0, reps: 0, targetSeconds: 1500, targetDistanceMeters: 5000)
        #expect(CardioSetRow.paceLine(setEntry: planned, unit: .km) == "5:00 /km · 12.0 km/h")
        let timeOnly = SetEntry(weightKg: 0, reps: 0, durationSeconds: 1530)
        #expect(CardioSetRow.paceLine(setEntry: timeOnly, unit: .km) == nil)
        #expect(done.cardioSummary(unit: .km) == "5.00 km · 25:30 · 5:06 /km")
    }

    @Test("ticking an untouched cardio row logs its targets as what was done")
    func completingAdoptsTargets() {
        let run = ExerciseInfo(name: "Run", primary: [.quads], equipment: "treadmill", loggingStyle: .cardio)
        let planned = SetEntry(weightKg: 0, reps: 0, targetSeconds: 1200, targetDistanceMeters: 5000)
        let entry = WorkoutExerciseEntry(exercise: run, sets: [planned])
        let session = WorkoutSession(title: "Run", subtitle: "", startedAt: Date(), exercises: [entry])
        session.restHaptics = false
        session.completeSet(exerciseID: entry.id, setID: entry.sets[0].id)
        #expect(session.exercises[0].sets[0].durationSeconds == 1200)
        #expect(session.exercises[0].sets[0].distanceMeters == 5000)
        #expect(session.distanceMeters == 5000)
    }

    // MARK: - Store mapping

    @Test("time, distance and incline round-trip through SetLogModel, split into target vs done")
    func storeMapsBothWays() throws {
        let (store, context) = try makeStore()
        let exercise = treadmill(store)
        let routine = cardioRoutine(store, exercise: exercise)
        let session = store.startWorkout(routineID: routine.id)
        let set = try #require(session.exercises.first?.sets.first)
        #expect(set.targetSeconds == 1200)
        #expect(set.targetDistanceMeters == 5000)
        #expect(set.reps == 0)
        #expect(session.exercises[0].whyTitle == "From your plan")

        // Untouched: the store keeps the targets and reads them back as targets, not as done.
        store.sync(session: session)
        let detail = store.workoutDetail(id: try #require(session.workoutID))
        let resumed = try #require(detail.exercises.first?.sets.first)
        #expect(resumed.targetDistanceMeters == 5000)
        #expect(resumed.distanceMeters == nil)

        session.exercises[0].sets[0].durationSeconds = 1530
        session.exercises[0].sets[0].distanceMeters = 5200
        session.exercises[0].sets[0].inclinePercent = 1.5
        session.completeSet(exerciseID: session.exercises[0].id, setID: set.id)
        store.sync(session: session)

        let logs = try context.fetch(FetchDescriptor<SetLogModel>())
        let log = try #require(logs.first { $0.id == set.id })
        #expect(log.durationSeconds == 1530)
        #expect(log.distanceMeters == 5200)
        #expect(log.inclinePercent == 1.5)
        let back = SetEntry(model: log)
        #expect(back.distanceMeters == 5200)
        #expect(back.targetDistanceMeters == nil)
        #expect(back.inclinePercent == 1.5)
    }

    @Test("the next session pre-fills last session's time and distance and the why card says so")
    func prescriptionRepeatsLastRun() throws {
        let (store, _) = try makeStore()
        let exercise = treadmill(store)
        let routine = cardioRoutine(store, exercise: exercise)
        let first = store.startWorkout(routineID: routine.id)
        first.exercises[0].sets[0].durationSeconds = 1530
        first.exercises[0].sets[0].distanceMeters = 5200
        first.exercises[0].sets[0].inclinePercent = 2
        first.completeSet(exerciseID: first.exercises[0].id, setID: first.exercises[0].sets[0].id)
        let summary = store.finish(session: first)
        #expect(summary.distanceMeters == 5200)

        let second = store.startWorkout(routineID: routine.id)
        let set = try #require(second.exercises.first?.sets.first)
        #expect(set.targetSeconds == 1530)
        #expect(set.targetDistanceMeters == 5200)
        #expect(set.inclinePercent == 2)
        #expect(set.durationSeconds == nil)
        #expect(second.exercises[0].whyTitle == "Same as last time")
        // 1530 s over 5.2 km is 294 s/km — 4:54.
        #expect(second.exercises[0].whyBody?.contains("5.20 km · 25:30 · 4:54 /km") == true)
        #expect(second.exercises[0].lastSessions.first == "5.20 km · 25:30 · 4:54 /km")
        #expect(second.exercises[0].sparkline == [5200])

        let added = store.autoFilledEntry(for: exercise)
        #expect(added.sets.count == 1)
        #expect(added.sets[0].targetDistanceMeters == 5200)
        #expect(added.sets[0].reps == 0)
    }

    @Test("the history line for a cardio set and the workout's distance total")
    func historyLineAndTotals() throws {
        let (store, _) = try makeStore()
        let exercise = treadmill(store)
        let routine = cardioRoutine(store, exercise: exercise)
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].durationSeconds = 1530
        session.exercises[0].sets[0].distanceMeters = 5000
        session.completeSet(exerciseID: session.exercises[0].id, setID: session.exercises[0].sets[0].id)
        _ = store.finish(session: session)
        let detail = store.workoutDetail(id: try #require(session.workoutID))
        #expect(detail.distanceMeters == 5000)
        #expect(detail.volumeKg == 0)
        #expect(detail.exercises[0].sets[0].cardioSummary(unit: .km) == "5.00 km · 25:30 · 5:06 /km")
        let records = store.personalRecords().first { $0.exerciseName == "Treadmill Run" }?.records ?? []
        #expect(records.contains { $0.kindLabel == "Longest distance" })
        #expect(records.contains { $0.kindLabel == "Fastest pace" })
    }

    // MARK: - Routine builder, backup, plan share

    @Test("a planned cardio set starts with a time target and no reps, and keeps its distance")
    func plannedCardioSet() throws {
        let initial = PlannedSetDraft.initial(for: .cardio)
        #expect(initial.targetReps == nil)
        #expect(initial.targetSeconds == 20 * 60)
        #expect(PlannedSetDraft.initial(for: .weightReps).targetReps == 8)

        let (store, _) = try makeStore()
        let exercise = treadmill(store)
        let routine = cardioRoutine(store, exercise: exercise)
        let drafts = try #require(store.routineDrafts(id: routine.id)).drafts
        #expect(drafts.first?.sets.first?.targetDistanceMeters == 5000)
        #expect(drafts.first?.sets.first?.targetSeconds == 1200)
    }

    @Test("a backup carries the planned distance, the logged distance and the incline")
    func backupRoundTrip() throws {
        let (source, sourceContext) = try makeStore()
        let exercise = treadmill(source)
        let routine = cardioRoutine(source, exercise: exercise)
        let session = source.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].durationSeconds = 1530
        session.exercises[0].sets[0].distanceMeters = 5000
        session.exercises[0].sets[0].inclinePercent = 3
        session.completeSet(exerciseID: session.exercises[0].id, setID: session.exercises[0].sets[0].id)
        _ = source.finish(session: session)

        let exported = BackupService.export(context: sourceContext)
        let document = try BackupCodec.decode(BackupCodec.encode(exported))
        #expect(document.routines.first?.exercises.first?.plannedSets.first?.targetDistanceMeters == 5000)
        let log = try #require(document.workouts.first?.exercises.first?.sets.first)
        #expect(log.inclinePercent == 3)
        #expect(log.distanceMeters == 5000)

        let (destination, destinationContext) = try makeStore()
        _ = BackupService.import(document: document, context: destinationContext)
        let planned = try destinationContext.fetch(FetchDescriptor<PlannedSetModel>())
        #expect(planned.first?.targetDistanceMeters == 5000)
        let logs = try destinationContext.fetch(FetchDescriptor<SetLogModel>())
        #expect(logs.first?.inclinePercent == 3)
        _ = destination
    }

    @Test("a shared plan carries the planned distance")
    func planShareRoundTrip() throws {
        let (source, sourceContext) = try makeStore()
        let exercise = treadmill(source)
        let routine = cardioRoutine(source, exercise: exercise)
        let document = try #require(PlanShareService.exportRoutine(id: routine.id, context: sourceContext))
        let decoded = try PlanCodec.decode(PlanCodec.encode(document))
        #expect(decoded.routines.first?.exercises.first?.sets.first?.targetDistanceMeters == 5000)

        let (_, destinationContext) = try makeStore()
        _ = PlanShareService.importPlan(document: decoded, context: destinationContext)
        let planned = try destinationContext.fetch(FetchDescriptor<PlannedSetModel>())
        #expect(planned.first?.targetDistanceMeters == 5000)
    }

    // MARK: - Units and voice

    @Test("the distance unit follows the weight unit on first read, then sticks")
    func distanceUnitDefault() {
        let suite = UserDefaults(suiteName: "CardioLoggingTests-\(UUID().uuidString)") ?? .standard
        suite.set(WeightUnit.lb.rawValue, forKey: Preferences.Key.weightUnit)
        let preferences = Preferences(suite: suite)
        #expect(preferences.distanceUnit == .mi)
        preferences.weightUnit = .kg
        #expect(Preferences(suite: suite).distanceUnit == .mi)
        preferences.distanceUnit = .km
        #expect(Preferences(suite: suite).distanceUnit == .km)
        #expect(preferences.formatDistance(meters: 5000, decimals: 1) == "5.0 km")
    }

    @Test("the voice context maps a cardio exercise instead of dropping it")
    func voiceContextMapsCardio() {
        #expect(VoiceLogController.loggingStyle(for: .cardio) == .cardio)
    }
}
