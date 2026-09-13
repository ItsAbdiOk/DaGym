import GymCore
import SwiftUI

/// Mutation handlers and sheet plumbing for `ActiveWorkoutView`. Every
/// mutation here ends with `store.sync(session:)` so the persisted
/// `WorkoutModel` never drifts from what's on screen.
extension ActiveWorkoutView {
    // MARK: Finish / discard

    func finishSession() {
        let summary = store.finish(session: session)
        onFinish(summary)
    }

    func discardSession() {
        store.discard(session: session)
        dismiss()
    }

    // MARK: Set completion

    func toggleDone(exerciseID: UUID, set: SetEntry) {
        if set.isDone {
            session.uncompleteSet(exerciseID: exerciseID, setID: set.id)
        } else {
            session.completeSet(exerciseID: exerciseID, setID: set.id)
        }
        store.sync(session: session)
    }

    // MARK: Timed holds

    func startTimedHold(exerciseID: UUID, setID: UUID) {
        guard let entry = session.exercises.first(where: { $0.id == exerciseID }),
              let set = entry.sets.first(where: { $0.id == setID }) else { return }
        session.startTimedHold(exerciseID: exerciseID, setID: setID, targetSeconds: set.targetSeconds)
    }

    func stopTimedHold() {
        session.stopTimedHold()
        store.sync(session: session)
    }

    // MARK: Exercise list edits

    func addSet(exerciseID: UUID, kind: SetKind) {
        guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let template = session.exercises[index].sets.last
        let newSet = SetEntry(kind: kind, weightKg: template?.weightKg ?? 0, reps: template?.reps ?? 0)
        session.exercises[index].sets.append(newSet)
        store.sync(session: session)
    }

    func removeExercise(id: UUID) {
        session.exercises.removeAll { $0.id == id }
        store.sync(session: session)
    }

    func replaceExercise(originalID: UUID, with candidate: ExerciseInfo) {
        guard let index = session.exercises.firstIndex(where: { $0.exercise.id == originalID }) else {
            return
        }
        session.exercises[index].exercise = candidate
        session.exercises[index].wasSubstitution = true
        store.sync(session: session)
        Haptics.confirm()
    }

    func addExercise(_ exercise: ExerciseInfo) {
        session.exercises.append(store.autoFilledEntry(for: exercise))
        store.sync(session: session)
    }

    // MARK: Per-exercise "…" menu

    var menuIsPresented: Binding<Bool> {
        Binding(get: { menuExerciseID != nil }, set: { if !$0 { menuExerciseID = nil } })
    }

    @ViewBuilder
    var exerciseMenuButtons: some View {
        if let id = menuExerciseID, let entry = session.exercises.first(where: { $0.id == id }) {
            Button("Swap exercise") { activeSheet = .swap(exercise: entry.exercise) }
            Button("Remove exercise", role: .destructive) { removeExercise(id: id) }
            Button("Add set") { addSet(exerciseID: id, kind: .working) }
            Button("Add warm-up set") { addSet(exerciseID: id, kind: .warmup) }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .keypad(let exerciseID, let setID, let field):
            keypadSheet(exerciseID: exerciseID, setID: setID, field: field)
        case .effort(let exerciseID, let setID):
            EffortPickerSheet(scale: $session.effortScale) { effort in
                session.completeSet(exerciseID: exerciseID, setID: setID, effort: effort)
                store.sync(session: session)
            }
        case .swap(let exercise):
            SwapExerciseSheet(exercise: exercise) { candidate in
                replaceExercise(originalID: exercise.id, with: candidate)
            }
        case .addExercise:
            ExercisePickerSheet(onPick: addExercise)
        case .reorder:
            ReorderExercisesSheet(session: session) {
                store.sync(session: session)
                activeSheet = nil
            }
        }
    }

    @ViewBuilder
    private func keypadSheet(exerciseID: UUID, setID: UUID, field: ActiveSheet.KeypadField) -> some View {
        if let ei = session.exercises.firstIndex(where: { $0.id == exerciseID }),
           let si = session.exercises[ei].sets.firstIndex(where: { $0.id == setID }) {
            let exercise = session.exercises[ei].exercise
            let previous = session.exercises[ei].sets[si].previous
            switch field {
            case .weight:
                WeightKeypadSheet(
                    title: "Weight", value: weightBinding(ei: ei, si: si), step: exercise.incrementKg,
                    bar: exercise.bar, last: previous, unit: "kg", onDone: { store.sync(session: session) }
                )
            case .reps:
                WeightKeypadSheet(
                    title: "Reps", value: repsBinding(ei: ei, si: si), step: 1, bar: nil,
                    last: previous, unit: "reps", onDone: { store.sync(session: session) }
                )
            }
        }
    }

    private func weightBinding(ei: Int, si: Int) -> Binding<Double> {
        Binding(
            get: { session.exercises[ei].sets[si].weightKg },
            set: { session.exercises[ei].sets[si].weightKg = $0 }
        )
    }

    private func repsBinding(ei: Int, si: Int) -> Binding<Double> {
        Binding(
            get: { Double(session.exercises[ei].sets[si].reps) },
            set: { session.exercises[ei].sets[si].reps = Int($0) }
        )
    }
}
