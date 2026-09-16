import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// `WorkoutStore.updateWorkoutNote` (OpenGym parity 20): editing a finished workout's session
/// note from History, and which workouts History may edit at all (`WorkoutDetail.canEditNotes`).
@MainActor
@Suite("Session note edited from History")
struct WorkoutNoteEditTests {
    /// A finished freestyle workout with one logged set on the first library exercise.
    private func finishWorkout(
        _ store: WorkoutStore, note: String = "", backfilled: Bool = false
    ) throws -> UUID {
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let session = backfilled
            ? store.startBackfill(
                date: Date().addingTimeInterval(-86_400 * 3), durationMinutes: 45, routineID: nil
            )
            : store.startFreestyle()
        var entry = store.autoFilledEntry(for: exercise, setCount: 1)
        entry.sets[0].isDone = true
        session.exercises = [entry]
        session.notes = note
        _ = store.finish(session: session)
        return try #require(session.workoutID)
    }

    @Test("a note added from History lands on the workout and reads back in its detail")
    func addsNote() throws {
        let store = try makeStore(seed: .firstLaunch)
        let id = try finishWorkout(store)
        #expect(store.workoutDetail(id: id).notes.isEmpty)

        #expect(store.updateWorkoutNote(id: id, text: "Felt strong, bar speed up"))
        #expect(store.workoutDetail(id: id).notes == "Felt strong, bar speed up")
    }

    @Test("an existing note is replaced, whitespace trimmed")
    func replacesNote() throws {
        let store = try makeStore(seed: .firstLaunch)
        let id = try finishWorkout(store, note: "Left shoulder pinching")

        store.updateWorkoutNote(id: id, text: "  Shoulder fine today \n")
        #expect(store.workoutDetail(id: id).notes == "Shoulder fine today")
    }

    @Test("an empty string clears the note")
    func emptyClears() throws {
        let store = try makeStore(seed: .firstLaunch)
        let id = try finishWorkout(store, note: "Deload week")

        store.updateWorkoutNote(id: id, text: "   ")
        #expect(store.workoutDetail(id: id).notes.isEmpty)
    }

    @Test("a backfilled workout's note is editable like any other")
    func backfilledIsEditable() throws {
        let store = try makeStore(seed: .firstLaunch)
        let id = try finishWorkout(store, backfilled: true)
        #expect(store.workoutDetail(id: id).canEditNotes)

        #expect(store.updateWorkoutNote(id: id, text: "Logged from memory"))
        #expect(store.workoutDetail(id: id).notes == "Logged from memory")
    }

    @Test("the save bumps changeToken so History redraws, and a no-op edit doesn't")
    func saveBumpsToken() throws {
        let store = try makeStore(seed: .firstLaunch)
        let id = try finishWorkout(store, note: "Same")
        let before = store.changeToken

        store.updateWorkoutNote(id: id, text: "Same")
        #expect(store.changeToken == before)
        store.updateWorkoutNote(id: id, text: "Changed")
        #expect(store.changeToken == before + 1)
    }

    @Test("an in-progress session's note is left to the live screen")
    func inProgressRefused() throws {
        let store = try makeStore(seed: .firstLaunch)
        let session = store.startFreestyle()
        let id = try #require(session.workoutID)

        #expect(!store.updateWorkoutNote(id: id, text: "Too early"))
        #expect(store.workout(id: id)?.notes.isEmpty == true)
        #expect(!store.workoutDetail(id: id).canEditNotes)
    }

    @Test("an imported Apple Health session has no note to edit")
    func healthImportRefused() throws {
        let store = try makeStore(seed: .firstLaunch)
        let external = HealthExternalWorkout(
            uuid: UUID().uuidString, start: Date().addingTimeInterval(-3_600), end: Date(),
            title: "Traditional Strength Training"
        )
        let imported = try #require(store.importExternalWorkout(external))

        let detail = store.workoutDetail(id: imported.id)
        #expect(!detail.canEditNotes)
        #expect(!store.updateWorkoutNote(id: imported.id, text: "Nope"))
    }

    @Test("an unknown id writes nothing")
    func unknownRefused() throws {
        let store = try makeStore(seed: .firstLaunch)
        let before = store.changeToken
        #expect(!store.updateWorkoutNote(id: UUID(), text: "Nowhere"))
        #expect(store.changeToken == before)
    }
}
