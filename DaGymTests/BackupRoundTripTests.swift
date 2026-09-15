import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Backup round trip")
struct BackupRoundTripTests {
    private func makeStore() throws -> (store: WorkoutStore, context: ModelContext) {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        return (WorkoutStore(context: context), context)
    }

    /// A routine with a routine-level rule and a per-exercise override, engine state on the slot,
    /// one finished workout flagged as a planned deload, a program with weeks, and an achievement.
    private func populate(_ store: WorkoutStore, context: ModelContext) throws -> UUID {
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ],
            overrideRule: .linear(incrementKg: 5)
        )
        let routine = store.saveRoutine(
            id: nil, name: "Push A", rule: .doubleProgression(low: 6, high: 8, incrementKg: 2.5),
            exercises: [draft]
        )
        let routineModel = try #require(store.fetchRoutineModel(id: routine.id))
        let slot = try #require(routineModel.exercises?.first)

        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[1].weightKg = 60
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)
        // Finishing rewrites the engine memory; the hand-set values below are what export must carry.
        slot.stallStateValue = StallState(consecutiveMisses: 2, lastWeightKg: 60)
        slot.trainingMaxKg = 100
        let workoutID = try #require(session.workoutID)
        let workout = try #require(store.fetchWorkoutModel(id: workoutID))
        try #require(workout.exercises?.first).wasPlannedDeload = true

        // A starter program needs all three of its routines present; the store is unseeded here.
        for name in ["Pull B", "Legs"] { _ = store.saveRoutine(id: nil, name: name, exercises: [draft]) }
        let program = try #require(store.createProgram(from: .pushPullLegs))
        store.startProgram(id: program.id)
        context.insert(AchievementModel(milestoneID: "first-workout", tier: "bronze", workoutID: workout.id))
        try context.save()
        return routine.id
    }

    @Test("export → import preserves rule JSON, stall, TM, planned deload, programs and achievements")
    func roundTripPreservesEngineState() throws {
        let (source, sourceContext) = try makeStore()
        let routineID = try populate(source, context: sourceContext)
        let exportedDocument = BackupService.export(context: sourceContext)
        let document = try BackupCodec.decode(BackupCodec.encode(exportedDocument))

        let exported = try #require(document.routines.first { $0.id == routineID })
        // Format 2 nests the rule and stall; the format-1 strings ride along for one more format.
        #expect(exported.rule == .doubleProgression(low: 6, high: 8, incrementKg: 2.5))
        #expect(exported.progressionRuleJSON?.isEmpty == false)
        #expect(exported.exercises.first?.rule == .linear(incrementKg: 5))
        #expect(exported.exercises.first?.progressionRuleJSON?.isEmpty == false)
        #expect(exported.exercises.first?.stall?.consecutiveMisses == 2)
        #expect(exported.exercises.first?.stall?.lastWeightKg == 60)
        #expect(exported.exercises.first?.trainingMaxKg == 100)
        #expect(document.workouts.first?.exercises.first?.wasPlannedDeload == true)
        #expect(document.workouts.first?.routineID == routineID)
        #expect(document.programs?.count == 1)
        #expect(document.achievements?.count == 1)

        let (destination, destinationContext) = try makeStore()
        let report = BackupService.import(document: document, context: destinationContext)
        #expect(report.problems.isEmpty)

        let routine = try #require(destination.fetchRoutineModel(id: routineID))
        // Compared as values: the import re-encodes the nested rule, so key order may differ.
        #expect(routine.progressionRuleValue == exported.resolvedRule)
        let slot = try #require(routine.exercises?.first)
        #expect(slot.overrideRuleValue == exported.exercises.first?.resolvedRule)
        #expect(slot.stallStateValue.consecutiveMisses == 2)
        #expect(slot.stallStateValue.lastWeightKg == 60)
        #expect(slot.trainingMaxKg == 100)
        #expect(destination.effectiveRule(routine: routine, routineExercise: slot) != nil)

        let workout = try #require(try destinationContext.fetch(FetchDescriptor<WorkoutModel>()).first)
        #expect(workout.exercises?.first?.wasPlannedDeload == true)
        #expect(workout.routineID == routineID)

        let programs = try destinationContext.fetch(FetchDescriptor<ProgramModel>())
        #expect(programs.count == 1)
        #expect(programs.first?.isActive == true)
        #expect(programs.first?.programWeeks?.count == StarterPrograms.weekKinds(for: .pushPullLegs).count)
        #expect(try destinationContext.fetchCount(FetchDescriptor<AchievementModel>()) == 1)
    }

    @Test("import rebuilds the PR cache from the imported workouts")
    func importRebuildsPersonalRecords() throws {
        let (source, sourceContext) = try makeStore()
        _ = try populate(source, context: sourceContext)
        let document = BackupService.export(context: sourceContext)

        let (destination, destinationContext) = try makeStore()
        BackupService.import(document: document, context: destinationContext)
        // By id, not by name search: the destination now has the seeded library too (a restore
        // seeds it if the store is empty), and "Bench Press" matches several seeded lifts before
        // the custom one. The exercise the imported workout actually used is the one under test.
        let imported = try #require(
            try destinationContext.fetch(FetchDescriptor<WorkoutModel>()).first?.exercises?.first?.exercise
        )
        #expect(destination.bestE1RMRecord(exerciseID: imported.id) != nil)
        let bench = try #require(
            destination.exercises(matching: "Bench Press").first { $0.id == imported.id }
        )
        #expect(bench.bestE1RM != nil)
    }

    @Test("importing twice adds no second program or achievement")
    func reimportIsIdempotentForNewTables() throws {
        let (source, sourceContext) = try makeStore()
        _ = try populate(source, context: sourceContext)
        let document = BackupService.export(context: sourceContext)

        let (_, destinationContext) = try makeStore()
        BackupService.import(document: document, context: destinationContext)
        BackupService.import(document: document, context: destinationContext)
        #expect(try destinationContext.fetchCount(FetchDescriptor<ProgramModel>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<AchievementModel>()) == 1)
    }

    @Test("untouched seeded exercises are not exported as overrides; an edited one is")
    func overridesCompareAgainstTheSeed() throws {
        let (store, context) = try makeStore()
        ExerciseSeeder.seedIfNeeded(context: context)
        #expect(BackupService.export(context: context).exercises.isEmpty)

        let bench = try #require(store.exercises(matching: "Barbell Bench Press - Medium Grip").first)
        store.updateExerciseSettings(id: bench.id, restSeconds: 90, barType: "olympic", incrementKg: 5)
        let document = BackupService.export(context: context)
        #expect(document.exercises.count == 1)
        #expect(document.exercises.first?.seedID == "Barbell_Bench_Press_-_Medium_Grip")

        let (destination, destinationContext) = try makeStore()
        ExerciseSeeder.seedIfNeeded(context: destinationContext)
        BackupService.import(document: document, context: destinationContext)
        let restored = try #require(
            destination.exercises(matching: "Barbell Bench Press - Medium Grip").first
        )
        #expect(restored.restSeconds == 90)
        #expect(restored.incrementKg == 5)
    }
}

/// The "new phone" path: wipe, restore, and be where you were — plus the individual fields and
/// rows that a restore used to lose on the way.
@MainActor
@Suite("Backup restore")
struct BackupRestoreTests {
    private func makeStore() throws -> (store: WorkoutStore, context: ModelContext) {
        let context = try makeContext()
        return (WorkoutStore(context: context), context)
    }

    /// A bare main-store context. `WorkoutStore(context:)` spins up two *extra* in-memory
    /// containers (photos and Health) behind the scenes, so tests that only need to export and
    /// import rows take this instead — a suite's worth of unnecessary containers is real memory
    /// in a test host that runs every suite in one process.
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer.dagym(inMemory: true))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The whole point of a backup: reset the device, import the file, and be where you were.
    /// Before this, "Reset everything" then "Import backup" in the same session imported every
    /// workout as an empty shell (the exercise library was gone and only re-seeded at launch), and
    /// none of the settings came back at all.
    @Test("wipe → restore brings back workouts, sets and every preference")
    func wipeThenRestoreIsFaithful() throws {
        let (source, sourceContext) = try makeStore()
        ExerciseSeeder.seedIfNeeded(context: sourceContext)
        let bench = try #require(source.exercises(matching: "Barbell Bench Press - Medium Grip").first)
        let workout = WorkoutModel(title: "Push A", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        sourceContext.insert(workout)
        let entry = WorkoutExerciseModel(
            order: 0, note: "seeded lift", excludedFromProgression: true, routineID: UUID(),
            exercise: source.fetchExerciseModel(id: bench.id), workout: workout
        )
        sourceContext.insert(entry)
        let set = SetLogModel(
            order: 0, kind: "working", weightKg: 100, reps: 5, isCompleted: true,
            workoutExercise: entry
        )
        sourceContext.insert(set)
        entry.sets = [set]
        workout.exercises = [entry]
        try sourceContext.save()

        let sourcePreferences = Preferences(suite: makeSuite("backup.roundtrip.source"))
        sourcePreferences.weightUnit = .lb
        sourcePreferences.defaultRestSeconds = 90
        sourcePreferences.weekStartsMonday = false
        sourcePreferences.effortScale = .rir
        sourcePreferences.weeklyGoal = 6
        sourcePreferences.restPauseSeconds = 25
        sourcePreferences.appearance = .dark
        let document = BackupService.export(
            context: sourceContext, preferences: sourcePreferences
        )

        // A wiped device: no exercises, default settings — exactly what `wipeAllData` leaves.
        let (destination, destinationContext) = try makeStore()
        let destinationPreferences = Preferences(suite: makeSuite("backup.roundtrip.destination"))
        #expect(try destinationContext.fetchCount(FetchDescriptor<ExerciseModel>()) == 0)

        let report = BackupService.import(
            document: document, context: destinationContext, preferences: destinationPreferences
        )

        // The seeded exercise resolved, so the workout kept its sets instead of arriving empty.
        #expect(report.problems.isEmpty)
        let restored = try #require(try destinationContext.fetch(FetchDescriptor<WorkoutModel>()).first)
        let restoredEntry = try #require(restored.exercises?.first)
        #expect(restoredEntry.sets?.count == 1)
        #expect(restoredEntry.sets?.first?.weightKg == 100)
        #expect(restoredEntry.exercise?.seedID == "Barbell_Bench_Press_-_Medium_Grip")
        #expect(destination.exercises(matching: "Barbell Bench Press").isEmpty == false)

        // …and the settings came back.
        #expect(report.preferencesRestored)
        #expect(destinationPreferences.weightUnit == .lb)
        #expect(destinationPreferences.effortScale == .rir)
        #expect(destinationPreferences.defaultRestSeconds == 90)
        #expect(destinationPreferences.weeklyGoal == 6)
        #expect(destinationPreferences.weekStartsMonday == false)
        #expect(destinationPreferences.restPauseSeconds == 25)
        #expect(destinationPreferences.appearance == .dark)
    }

    @Test("restoring an export from before preferences were widened leaves unknown keys alone")
    func olderExportDoesNotResetUnknownPreferences() throws {
        let context = try makeContext()
        let document = BackupDocument(
            exportedAt: Date(), appVersion: "1.0 (1)", preferences: BackupPreferences()
        )
        let preferences = Preferences(suite: makeSuite("backup.roundtrip.older"))
        preferences.restPauseSeconds = 40
        preferences.appearance = .dark
        BackupService.import(document: document, context: context, preferences: preferences)
        #expect(preferences.restPauseSeconds == 40)
        #expect(preferences.appearance == .dark)
    }

    @Test("excludedFromProgression and routineID survive a round trip")
    func perExerciseFlagsSurvive() throws {
        let (source, sourceContext) = try makeStore()
        let squat = source.createCustomExercise(
            name: "Zercher Squat", primary: [.quads], equipment: "barbell", style: .weightReps
        )
        let routineID = UUID()
        let workout = WorkoutModel(title: "Legs", startedAt: Date())
        sourceContext.insert(workout)
        let entry = WorkoutExerciseModel(
            order: 0, excludedFromProgression: true, routineID: routineID,
            exercise: source.fetchExerciseModel(id: squat.id), workout: workout
        )
        sourceContext.insert(entry)
        workout.exercises = [entry]
        try sourceContext.save()

        let document = BackupService.export(context: sourceContext)
        let destinationContext = try makeContext()
        BackupService.import(document: document, context: destinationContext)
        let restored = try #require(
            try destinationContext.fetch(FetchDescriptor<WorkoutModel>()).first?.exercises?.first
        )
        #expect(restored.excludedFromProgression)
        #expect(restored.routineID == routineID)
    }

    /// Deleting a custom exercise nulls the link on its logged rows but keeps them, so history
    /// totals don't move. Export used to drop exactly those rows on the floor — silently.
    @Test("history on a deleted custom exercise survives the backup, with a problem reported")
    func historyOnDeletedExerciseSurvives() throws {
        let (source, sourceContext) = try makeStore()
        let ghost = source.createCustomExercise(
            name: "Ghost Lift", primary: [.chest], equipment: "other", style: .weightReps
        )
        let workout = WorkoutModel(title: "Old Session", startedAt: Date())
        sourceContext.insert(workout)
        let entry = WorkoutExerciseModel(
            order: 0, exercise: source.fetchExerciseModel(id: ghost.id), workout: workout
        )
        sourceContext.insert(entry)
        let set = SetLogModel(
            order: 0, kind: "working", weightKg: 60, reps: 8, isCompleted: true, workoutExercise: entry
        )
        sourceContext.insert(set)
        entry.sets = [set]
        workout.exercises = [entry]
        try sourceContext.save()
        #expect(source.deleteCustomExercise(id: ghost.id))

        let result = BackupService.exportResult(context: sourceContext)
        let exported = try #require(result.document.workouts.first?.exercises.first)
        #expect(exported.exerciseName == BackupService.deletedExerciseName)
        #expect(exported.sets.count == 1)
        #expect(exported.sets.first?.weightKg == 60)
        #expect(result.problems.count == 1)

        // …and it restores as a placeholder custom exercise rather than vanishing.
        let destinationContext = try makeContext()
        BackupService.import(document: result.document, context: destinationContext)
        let restored = try #require(
            try destinationContext.fetch(FetchDescriptor<WorkoutModel>()).first?.exercises?.first
        )
        #expect(restored.sets?.first?.reps == 8)
    }

    @Test("a restored equipment profile is active again when nothing else is")
    func equipmentProfileStaysActive() throws {
        let sourceContext = try makeContext()
        sourceContext.insert(EquipmentProfileModel(name: "Home", isActive: true, barKg: 20))
        try sourceContext.save()
        let document = BackupService.export(context: sourceContext)

        let destinationContext = try makeContext()
        BackupService.import(document: document, context: destinationContext)
        let profiles = try destinationContext.fetch(FetchDescriptor<EquipmentProfileModel>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.isActive == true)
    }

    /// `ScheduleModel` is created lazily the first time anything reads the schedule, so merely
    /// opening the schedule screen before restoring used to leave a blank row that swallowed the
    /// backup's schedule entirely.
    @Test("a lazily-created blank schedule row doesn't swallow the backup's schedule")
    func blankScheduleRowIsFilled() throws {
        let sourceContext = try makeContext()
        sourceContext.insert(ScheduleModel(scheduleJSON: #"{"mon":["push"]}"#))
        try sourceContext.save()
        let document = BackupService.export(context: sourceContext)

        let destinationContext = try makeContext()
        destinationContext.insert(ScheduleModel())
        try destinationContext.save()
        BackupService.import(document: document, context: destinationContext)
        let restored = try #require(
            try destinationContext.fetch(FetchDescriptor<ScheduleModel>()).first
        )
        #expect(restored.scheduleJSON == #"{"mon":["push"]}"#)
    }

    @Test("a schedule the user has actually filled in is never overwritten by an import")
    func realScheduleIsNotOverwritten() throws {
        let sourceContext = try makeContext()
        sourceContext.insert(ScheduleModel(scheduleJSON: #"{"mon":["push"]}"#))
        try sourceContext.save()
        let document = BackupService.export(context: sourceContext)

        let destinationContext = try makeContext()
        destinationContext.insert(ScheduleModel(scheduleJSON: #"{"tue":["pull"]}"#))
        try destinationContext.save()
        BackupService.import(document: document, context: destinationContext)
        let restored = try #require(
            try destinationContext.fetch(FetchDescriptor<ScheduleModel>()).first
        )
        #expect(restored.scheduleJSON == #"{"tue":["pull"]}"#)
    }

    @Test("an import lands on the same instant regardless of the device timezone")
    func restoreIsTimezoneStable() throws {
        let sourceContext = try makeContext()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = WorkoutModel(title: "Legs", startedAt: startedAt)
        sourceContext.insert(workout)
        try sourceContext.save()
        let data = try BackupCodec.encode(BackupService.export(context: sourceContext))

        let destinationContext = try makeContext()
        BackupService.import(
            document: try BackupCodec.decode(data), context: destinationContext
        )
        let restored = try #require(
            try destinationContext.fetch(FetchDescriptor<WorkoutModel>()).first
        )
        // ISO 8601 with an explicit offset: the instant is absolute, so no timezone can shift it.
        #expect(restored.startedAt.timeIntervalSince1970 == startedAt.timeIntervalSince1970)
    }
}
