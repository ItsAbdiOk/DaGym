import Foundation
import GymCore
import SwiftData
import Testing
import Vision

@testable import DaGym

/// Batch B5: exercise notes with scope (adopt 5), the gym check-in card (adopt 6), effort
/// analytics through the store (adopt 9), exercise detail actions (adopt 16) and the chart's
/// effort/reps data (adopt 21).
@MainActor
@Suite("Feature: notes, check-in, effort, exercise actions")
struct FeatureNotesCheckInTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeExercise(_ store: WorkoutStore, name: String = "Bench Press") -> ExerciseInfo {
        store.createCustomExercise(name: name, primary: [.chest], equipment: "barbell", style: .weightReps)
    }

    private func makeRoutine(_ store: WorkoutStore, exerciseID: UUID, name: String = "Push A") -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID, sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        return store.saveRoutine(id: nil, name: name, exercises: [draft]).id
    }

    /// Finishes one workout on the routine with the first set done at `weight`×`reps`, rated
    /// `rpe`, optionally with a session note; returns the workout id.
    @discardableResult
    private func finishWorkout(
        _ store: WorkoutStore, routineID: UUID, weight: Double = 60, reps: Int = 8, rpe: Double? = nil,
        note: String? = nil
    ) -> UUID? {
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].weightKg = weight
        session.exercises[0].sets[0].reps = reps
        session.exercises[0].sets[0].isDone = true
        session.exercises[0].sets[0].effort = rpe.map { Effort(rpe: $0) }
        session.exercises[0].note = note
        _ = store.finish(session: session)
        return session.workoutID
    }

    // MARK: - Notes (adopt 5)

    @Test("scoped notes round-trip newest first and merge with finished-workout session notes")
    func notesHistory() throws {
        let store = try makeStore()
        let exercise = makeExercise(store)
        let routineID = makeRoutine(store, exerciseID: exercise.id)
        finishWorkout(store, routineID: routineID, note: "Elbows tucked")
        let base = Date()
        let id = exercise.id
        store.addExerciseNote(exerciseID: id, text: "  Try 62.5 next  ", scope: .next, createdAt: base)
        store.addExerciseNote(exerciseID: id, text: "Pause at chest", scope: .always, createdAt: base + 1)
        #expect(store.addExerciseNote(exerciseID: exercise.id, text: "   ", scope: .always) == nil)
        #expect(store.addExerciseNote(exerciseID: exercise.id, text: "session only", scope: .session) == nil)

        let notes = store.exerciseNotes(exerciseID: exercise.id)
        #expect(notes.map(\.text) == ["Pause at chest", "Try 62.5 next", "Elbows tucked"])
        #expect(notes.map(\.scope) == [.always, .next, .session])
        #expect(notes[2].workoutID != nil)

        store.deleteExerciseNote(id: notes[0].id)
        #expect(store.exerciseNotes(exerciseID: exercise.id).count == 2)
    }

    @Test("pinnedNote prefers the newest always note over a next-time note")
    func pinnedPrefersAlways() throws {
        let store = try makeStore()
        let exercise = makeExercise(store)
        let base = Date()
        store.addExerciseNote(exerciseID: exercise.id, text: "next", scope: .next, createdAt: base + 5)
        let id = exercise.id
        store.addExerciseNote(exerciseID: id, text: "old always", scope: .always, createdAt: base)
        store.addExerciseNote(exerciseID: id, text: "new always", scope: .always, createdAt: base + 1)
        #expect(store.pinnedNote(exerciseID: exercise.id)?.text == "new always")
        #expect(store.pinnedNote(exerciseID: UUID()) == nil)
    }

    @Test("a next-time note shows through the next session and retires after it")
    func nextTimeNoteRetires() throws {
        let store = try makeStore()
        let exercise = makeExercise(store)
        let routineID = makeRoutine(store, exerciseID: exercise.id)
        let authored = finishWorkout(store, routineID: routineID)
        store.addExerciseNote(
            exerciseID: exercise.id, text: "Go heavier", scope: .next, workoutID: authored,
            createdAt: Date(timeIntervalSinceNow: -60)
        )
        #expect(store.pinnedNote(exerciseID: exercise.id)?.text == "Go heavier")

        let next = store.startWorkout(routineID: routineID)
        #expect(store.pinnedNote(exerciseID: exercise.id, workoutID: next.workoutID)?.text == "Go heavier")
        next.exercises[0].sets[0].isDone = true
        _ = store.finish(session: next)
        #expect(store.pinnedNote(exerciseID: exercise.id, workoutID: next.workoutID)?.text == "Go heavier")

        let after = store.startWorkout(routineID: routineID)
        #expect(store.pinnedNote(exerciseID: exercise.id, workoutID: after.workoutID) == nil)
    }

    // MARK: - Gym card (adopt 6)

    @Test("gym cards keep rail order, open on the last used one and delete cleanly")
    func gymCardStore() throws {
        let store = try makeStore()
        #expect(store.addGymCard(name: "x", value: "   ", symbology: .qr) == nil)
        let first = try #require(store.addGymCard(name: "  ", value: "1234567890128", symbology: .ean13))
        let second = try #require(store.addGymCard(name: "PureGym", value: "https://gym/qr", symbology: .qr))
        #expect(first.name == "Gym card")
        #expect(store.gymCards().map(\.id) == [first.id, second.id])
        #expect(store.lastUsedGymCard()?.id == first.id)

        store.markGymCardUsed(id: second.id)
        #expect(store.lastUsedGymCard()?.id == second.id)

        store.reorderGymCards([second.id, first.id])
        #expect(store.gymCards().map(\.id) == [second.id, first.id])

        store.renameGymCard(id: first.id, name: "The Gym")
        #expect(store.gymCards().first { $0.id == first.id }?.name == "The Gym")

        store.deleteGymCard(id: second.id)
        #expect(store.gymCards().map(\.id) == [first.id])
        #expect(store.gymCards()[0].symbology == .ean13)
    }

    @Test("Vision symbologies map to stored cases; 1-D retail codes draw as Code 128")
    func symbologyMapping() {
        #expect(GymCardSymbology(vision: .qr) == .qr)
        #expect(GymCardSymbology(vision: .ean13) == .ean13)
        #expect(GymCardSymbology(vision: .code39Checksum) == .code39)
        #expect(GymCardSymbology(vision: .codabar) == .code128)
        #expect(GymCardSymbology.ean13.generatorName == "CICode128BarcodeGenerator")
        #expect(GymCardSymbology.qr.generatorName == "CIQRCodeGenerator")
        #expect(GymCardSymbology.qr.isTwoDimensional)
        #expect(!GymCardSymbology.ean13.isTwoDimensional)
    }

    @Test("BarcodeRenderer regenerates QR and Code 128 images from the value alone")
    func barcodeRendering() {
        let qr = BarcodeRenderer.image(value: "https://gym/qr", symbology: .qr)
        #expect(qr != nil)
        #expect((qr?.size.width ?? 0) > 0)
        let code128 = BarcodeRenderer.image(value: "1234567890128", symbology: .ean13)
        #expect(code128 != nil)
        #expect((code128?.size.width ?? 0) > (code128?.size.height ?? 0))
        #expect(BarcodeRenderer.image(value: "", symbology: .qr) == nil)
    }

    @Test("show-gym-card intent flag fires once")
    func intentFlag() {
        #expect(!PendingGymCardIntentAction.consumeShowGymCard())
        PendingGymCardIntentAction.requestShowGymCard()
        #expect(PendingGymCardIntentAction.consumeShowGymCard())
        #expect(!PendingGymCardIntentAction.consumeShowGymCard())
    }

    // MARK: - Effort analytics (adopt 9)

    @Test("effortSeries reports rated weeks, coverage and a hardest-first histogram")
    func effortSeriesThroughStore() throws {
        let store = try makeStore()
        let exercise = makeExercise(store)
        let routineID = makeRoutine(store, exerciseID: exercise.id)
        #expect(store.effortSeries(weeks: 8).ratedSets == 0)

        finishWorkout(store, routineID: routineID, rpe: 8)
        finishWorkout(store, routineID: routineID, rpe: 10)
        finishWorkout(store, routineID: routineID)

        let bundle = store.effortSeries(weeks: 8)
        #expect(bundle.ratedSets == 2)
        #expect(bundle.weeks.count == 1)
        #expect(bundle.weeks[0].meanRPE == 9)
        #expect(bundle.weeks[0].meanValue(scale: .rir) == 1)
        #expect(bundle.weeks[0].totalSets == 3)
        #expect(bundle.histogram.first?.effort.rpe == 10)
        #expect(bundle.histogram.map(\.count) == [1, 0, 1, 0, 0, 0])
    }

    // MARK: - Exercise detail actions (adopt 16)

    @Test("addExercise appends a slot with planned sets in the routine's rep range")
    func addToRoutine() throws {
        let store = try makeStore()
        let bench = makeExercise(store)
        let routineID = makeRoutine(store, exerciseID: bench.id)
        let fly = makeExercise(store, name: "Cable Fly")

        store.addExercise(id: fly.id, toRoutine: routineID)
        let loaded = try #require(store.routineDrafts(id: routineID))
        #expect(loaded.drafts.map(\.exerciseID) == [bench.id, fly.id])
        #expect(loaded.drafts[1].sets.count == 3)
        #expect(loaded.drafts[1].sets[0].targetReps == 6)
        #expect(loaded.drafts[1].sets[0].targetRepsHigh == 8)
        #expect(store.routinesUsing(exerciseID: fly.id).map(\.id) == [routineID])

        store.addExercise(id: UUID(), toRoutine: routineID)
        #expect(store.routineDrafts(id: routineID)?.drafts.count == 2)
    }

    @Test("updateCustomExercise rewrites identity fields but leaves seeded exercises alone")
    func editCustom() throws {
        let store = try makeStore()
        let custom = makeExercise(store)
        let fields = CustomExerciseFields(
            name: "  Paused Bench  ", primary: [.triceps], equipment: "dumbbell", style: .bodyweightReps,
            isPerSide: true, barType: nil
        )
        store.updateCustomExercise(id: custom.id, fields: fields)
        let model = try #require(store.fetchExerciseModel(id: custom.id))
        #expect(model.name == "Paused Bench")
        #expect(model.primaryMuscles == ["triceps"])
        #expect(model.equipment == "dumbbell")
        #expect(model.loggingStyle == "bodyweightReps")
        #expect(model.isPerSide)

        let seeded = ExerciseModel(seedID: "seed-1", name: "Seeded Row", isCustom: false)
        store.context.insert(seeded)
        store.save()
        store.updateCustomExercise(id: seeded.id, fields: fields)
        #expect(store.fetchExerciseModel(id: seeded.id)?.name == "Seeded Row")
    }

    @Test("deleteCustomExercise removes routine slots, keeps history rows, refuses seeded")
    func deleteCustom() throws {
        let store = try makeStore()
        let custom = makeExercise(store)
        let routineID = makeRoutine(store, exerciseID: custom.id)
        _ = makeRoutine(store, exerciseID: custom.id, name: "Push B")
        finishWorkout(store, routineID: routineID)
        #expect(store.routinesUsing(exerciseID: custom.id).count == 2)

        #expect(store.deleteCustomExercise(id: custom.id))
        #expect(store.fetchExerciseModel(id: custom.id) == nil)
        #expect(store.routineDrafts(id: routineID)?.drafts.isEmpty == true)
        let rows = (try? store.context.fetch(FetchDescriptor<WorkoutExerciseModel>())) ?? []
        #expect(rows.count == 1)
        #expect(rows[0].exercise == nil)

        let seeded = ExerciseModel(seedID: "seed-2", name: "Seeded Squat", isCustom: false)
        store.context.insert(seeded)
        store.save()
        #expect(!store.deleteCustomExercise(id: seeded.id))
        #expect(store.fetchExerciseModel(id: seeded.id) != nil)
    }

    // MARK: - Chart effort dots + reps fallback (adopt 21)

    @Test("exerciseSeries carries the top set's rating and flips to reps when never loaded")
    func chartEffortAndRepsFallback() throws {
        let store = try makeStore()
        let bench = makeExercise(store)
        let benchRoutine = makeRoutine(store, exerciseID: bench.id)
        finishWorkout(store, routineID: benchRoutine, weight: 60, reps: 8, rpe: 9)
        finishWorkout(store, routineID: benchRoutine, weight: 65, reps: 6)
        let loaded = store.exerciseSeries(exerciseID: bench.id, months: nil)
        #expect(!loaded.neverLoaded)
        #expect(loaded.topSetRPE.count == 1)
        #expect(loaded.topSetRPE.values.first == 9)

        let pullUp = store.createCustomExercise(
            name: "Pull-Up", primary: [.lats], equipment: "bodyweight", style: .bodyweightReps
        )
        let pullRoutine = makeRoutine(store, exerciseID: pullUp.id)
        finishWorkout(store, routineID: pullRoutine, weight: 0, reps: 8)
        finishWorkout(store, routineID: pullRoutine, weight: 0, reps: 11)
        let unloaded = store.exerciseSeries(exerciseID: pullUp.id, months: nil)
        #expect(unloaded.neverLoaded)
        #expect(unloaded.e1rm.isEmpty)
        #expect(unloaded.bestReps.map(\.value) == [8, 11])
        #expect(unloaded.totalReps.map(\.value) == [8, 11])
    }
}
