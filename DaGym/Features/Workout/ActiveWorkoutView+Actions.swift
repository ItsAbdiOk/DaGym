import GymCore
import SwiftUI

/// Mutation handlers and sheet plumbing for `ActiveWorkoutView`. Every
/// mutation here ends with `store.sync(session:)` so the persisted
/// `WorkoutModel` never drifts from what's on screen.
extension ActiveWorkoutView {
    // MARK: Finish / discard

    func finishSession() {
        RestActivityController.shared.endNow()
        let summary = store.finish(
            session: session, weeklyGoal: preferences.weeklyGoal,
            calendar: preferences.trainingCalendar, unit: preferences.weightUnit
        )
        onFinish(summary)
    }

    func discardSession() {
        RestActivityController.shared.endNow()
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

    /// The effort chip completes an open set; on a set that's already done it just edits the
    /// effort, so re-tapping the chip never restarts rest.
    func logEffort(exerciseID: UUID, setID: UUID, effort: Effort) {
        let entry = session.exercises.first(where: { $0.id == exerciseID })
        let isDone = entry?.sets.first(where: { $0.id == setID })?.isDone ?? false
        if isDone {
            session.setEffort(exerciseID: exerciseID, setID: setID, effort: effort)
        } else {
            session.completeSet(exerciseID: exerciseID, setID: setID, effort: effort)
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
        session.addSet(exerciseID: exerciseID, kind: kind)
        store.sync(session: session)
    }

    func removeExercise(id: UUID) {
        session.exercises.removeAll { $0.id == id }
        store.sync(session: session)
    }

    /// An entry with logged sets keeps them; the candidate is added after it as its own entry.
    /// One with nothing logged is swapped in place.
    func replaceExercise(entryID: UUID, with candidate: ExerciseInfo, keepInSuperset: Bool) {
        if session.hasLoggedSets(entryID: entryID) {
            let substitute = store.autoFilledEntry(for: candidate)
            session.insertSubstitute(substitute, after: entryID, keepInSuperset: keepInSuperset)
        } else {
            session.replaceInPlace(entryID: entryID, with: candidate)
        }
        store.sync(session: session)
        Haptics.confirm()
    }

    func addExercise(_ exercise: ExerciseInfo) {
        session.exercises.append(store.autoFilledEntry(for: exercise))
        store.sync(session: session)
    }

    /// Delete / change-type swipe actions on `SetRow`.
    func deleteSet(exerciseID: UUID, setID: UUID) {
        session.removeSet(exerciseID: exerciseID, setID: setID)
        store.sync(session: session)
    }

    func changeSetKind(exerciseID: UUID, setID: UUID, to kind: SetKind) {
        session.changeSetKind(exerciseID: exerciseID, setID: setID, to: kind)
        store.sync(session: session)
    }

    /// "Generate warm-ups" from the "…" menu (plan §7).
    func generateWarmups(exerciseID: UUID) {
        session.addWarmups(exerciseID: exerciseID)
        store.sync(session: session)
    }

    func setNote(exerciseID: UUID, text: String) {
        guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        session.exercises[index].note = text.isEmpty ? nil : text
        store.sync(session: session)
    }

    // MARK: Rest alerts

    /// Preference-gated sound + screen flash at 3-2-1-0. Haptics are gated the same way inside
    /// `WorkoutSession.tickRest` via `session.restHaptics`.
    func handleRestTick(_ remaining: Int) {
        guard remaining <= 3 else { return }
        if preferences.restSound {
            restAlertPlayer.bleep(longer: remaining == 0)
        }
        if preferences.restScreenFlash, remaining == 0 {
            triggerRestFlash()
        }
    }

    private func triggerRestFlash() {
        withAnimation(.easeOut(duration: 0.15)) { flashOpacity = 0.6 }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0 }
        }
    }

    // MARK: Per-exercise "…" menu

    var menuIsPresented: Binding<Bool> {
        Binding(get: { menuExerciseID != nil }, set: { if !$0 { menuExerciseID = nil } })
    }

    @ViewBuilder
    var exerciseMenuButtons: some View {
        if let id = menuExerciseID, let entry = session.exercises.first(where: { $0.id == id }) {
            Button("Swap exercise") { activeSheet = .swap(entryID: id, exercise: entry.exercise) }
            Button("Remove exercise", role: .destructive) { removeExercise(id: id) }
            Button("Add set") { addSet(exerciseID: id, kind: .working) }
            Button("Add warm-up set") { addSet(exerciseID: id, kind: .warmup) }
            Button("Generate warm-ups") { generateWarmups(exerciseID: id) }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .keypad(let exerciseID, let setID, let field):
            keypadSheet(exerciseID: exerciseID, setID: setID, field: field)
        case .effort(let exerciseID, let setID):
            EffortPickerSheet(scale: effortScaleBinding) { effort in
                logEffort(exerciseID: exerciseID, setID: setID, effort: effort)
            }
        case .swap(let entryID, let exercise):
            SwapExerciseSheet(
                exercise: exercise, loggedSetCount: session.doneCount(entryID: entryID),
                isInSuperset: session.isInSuperset(entryID: entryID)
            ) { candidate, keepInSuperset in
                replaceExercise(entryID: entryID, with: candidate, keepInSuperset: keepInSuperset)
            }
        case .addExercise:
            ExercisePickerSheet(onPick: addExercise)
        case .reorder:
            ReorderExercisesSheet(session: session) {
                store.sync(session: session)
                activeSheet = nil
            }
        case .notes(let exerciseID):
            notesSheet(exerciseID: exerciseID)
        }
    }

    /// Writes to both the session (what the sheet displays) and `Preferences` (the source of
    /// truth new sessions seed from), so toggling RPE/RIR mid-workout sticks for next time.
    private var effortScaleBinding: Binding<Effort.Scale> {
        Binding(
            get: { session.effortScale },
            set: { session.effortScale = $0; preferences.effortScale = $0 }
        )
    }

    @ViewBuilder
    private func notesSheet(exerciseID: UUID) -> some View {
        if let entry = session.exercises.first(where: { $0.id == exerciseID }) {
            NotesSheet(title: entry.exercise.name, text: entry.note ?? "") { text in
                setNote(exerciseID: exerciseID, text: text)
            }
        }
    }

    @ViewBuilder
    private func keypadSheet(exerciseID: UUID, setID: UUID, field: ActiveSheet.KeypadField) -> some View {
        if let ei = session.exercises.firstIndex(where: { $0.id == exerciseID }),
           let si = session.exercises[ei].sets.firstIndex(where: { $0.id == setID }) {
            let exercise = session.exercises[ei].exercise
            let previousWeight = session.exercises[ei].sets[si].previousWeightKg
            let previousReps = session.exercises[ei].sets[si].previousReps
            switch field {
            case .weight:
                WeightKeypadSheet(
                    title: "Weight", value: weightBinding(ei: ei, si: si), step: exercise.incrementKg,
                    bar: exercise.bar, last: previousWeight.map { preferences.formatWeight(kg: $0) },
                    unit: preferences.weightUnit, onDone: { store.sync(session: session) }
                )
            case .reps:
                WeightKeypadSheet(
                    title: "Reps", value: repsBinding(ei: ei, si: si), step: 1, bar: nil,
                    last: previousReps.map(String.init), unit: nil,
                    onDone: { store.sync(session: session) }
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
