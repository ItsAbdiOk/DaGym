import GymCore
import SwiftUI

/// Mutation handlers and sheet plumbing for `ActiveWorkoutView`. Every
/// mutation here ends with `store.sync(session:)` so the persisted
/// `WorkoutModel` never drifts from what's on screen.
extension ActiveWorkoutView {
    // MARK: Finish / discard

    func finishSession() {
        cancelPendingNoteSync()
        RestActivityController.shared.endNow()
        let summary = store.finish(
            session: session, weeklyGoal: preferences.weeklyGoal,
            calendar: preferences.trainingCalendar, unit: preferences.weightUnit
        )
        onFinish(summary)
    }

    func discardSession() {
        cancelPendingNoteSync()
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

    /// Removes the entry and offers a 5 s undo that puts it back in the same slot.
    func removeExercise(id: UUID) {
        guard let index = session.exercises.firstIndex(where: { $0.id == id }) else { return }
        let removed = session.exercises.remove(at: index)
        // Removing one half of a superset used to leave the survivor carrying the pair's group
        // id, so it stayed a "superset" of one: the rest timer kept waiting on a partner that no
        // longer existed and never started.
        session.normalizeSupersets()
        store.sync(session: session)
        undoAction = UndoAction(message: "Removed \(removed.exercise.name)") {
            session.exercises.insert(removed, at: min(index, session.exercises.count))
            session.normalizeSupersets()
            store.sync(session: session)
        }
    }

    /// "Superset with previous / next" and "Unpair" from the exercise menu.
    func pairSuperset(entryID: UUID, with direction: WorkoutSession.PairDirection) {
        session.pairSuperset(entryID: entryID, with: direction)
        store.sync(session: session)
    }

    func unpairSuperset(entryID: UUID) {
        session.unpairSuperset(entryID: entryID)
        store.sync(session: session)
    }

    /// Appends a saved routine's exercises to the session (header menu → "Add routine…").
    func appendRoutine(id: UUID) {
        store.appendRoutine(id: id, to: session, calendar: preferences.trainingCalendar)
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

    /// Delete / change-type swipe actions on `SetRow`. A deleted set gets a 5 s undo.
    func deleteSet(exerciseID: UUID, setID: UUID) {
        guard let ei = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = session.exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        let removed = session.exercises[ei].sets[si]
        let countBefore = session.exercises[ei].sets.count
        session.removeSet(exerciseID: exerciseID, setID: setID)
        guard session.exercises[ei].sets.count < countBefore else { return }
        store.sync(session: session)
        undoAction = UndoAction(message: "Deleted set") {
            session.insertSet(removed, at: si, exerciseID: exerciseID)
            store.sync(session: session)
        }
    }

    /// Drop-set / rest-pause swipe shortcuts: a seeded row straight under this one.
    func insertSet(exerciseID: UUID, after setID: UUID, kind: SetKind) {
        session.insertSet(exerciseID: exerciseID, after: setID, kind: kind)
        store.sync(session: session)
    }

    /// The ± steppers on `SetRow`.
    func adjustSet(exerciseID: UUID, setID: UUID, weightDelta: Double = 0, repsDelta: Int = 0) {
        session.adjustSet(
            exerciseID: exerciseID, setID: setID, weightDelta: weightDelta, repsDelta: repsDelta
        )
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

    /// The "…" sheet for one entry (`ExerciseActionsSheet`). Actions that open another sheet
    /// (swap, notes) set `activeSheet` after this one has dismissed itself.
    @ViewBuilder
    var exerciseActionsSheet: some View {
        if let id = menuExerciseID, let index = session.exercises.firstIndex(where: { $0.id == id }) {
            let entry = session.exercises[index]
            ExerciseActionsSheet(
                options: .init(
                    name: entry.exercise.name, isCardio: entry.isCardio, hasPrevious: index > 0,
                    hasNext: index + 1 < session.exercises.count, isInSuperset: entry.supersetGroup != nil
                )
            ) { action in
                perform(action, on: id, entry: entry)
            }
        }
    }

    private func perform(_ action: ExerciseActionsSheet.Action, on id: UUID, entry: WorkoutExerciseEntry) {
        switch action {
        case .addSet(let kind): addSet(exerciseID: id, kind: kind)
        case .generateWarmups: generateWarmups(exerciseID: id)
        case .pairPrevious: pairSuperset(entryID: id, with: .previous)
        case .pairNext: pairSuperset(entryID: id, with: .next)
        case .unpair: unpairSuperset(entryID: id)
        case .notes: activeSheet = .notes(exerciseID: id)
        case .swap: activeSheet = .swap(entryID: id, exercise: entry.exercise)
        case .remove: removeExercise(id: id)
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
        case .addRoutine:
            // Fetched when the sheet is asked for, not in this builder — SwiftUI may evaluate
            // sheet content more than once per presentation.
            AddRoutineSheet(routines: addRoutineChoices) { routine in appendRoutine(id: routine.id) }
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
        if let entry = session.exercises.first(where: { $0.id == exerciseID }),
           let set = entry.sets.first(where: { $0.id == setID }) {
            let ids = SetAddress(exerciseID: exerciseID, setID: setID)
            switch field {
            case .weight, .reps:
                SetKeypadSheet(
                    exercise: entry.exercise, set: set, setNumber: setNumber(of: setID, in: entry),
                    initialField: field == .reps ? .reps : .weight, effortScale: session.effortScale,
                    weight: weightBinding(ids), reps: repsBinding(ids), effort: effortBinding(ids),
                    inventory: inventory,
                    onLog: { effort in logSet(exerciseID: exerciseID, setID: setID, effort: effort) }
                )
            case .minutes, .distance, .incline:
                cardioKeypad(field: field, set: set, ids: ids)
            }
        }
    }

    /// "set 2" in the keypad's title: the row's 1-based position within its exercise.
    private func setNumber(of setID: UUID, in entry: WorkoutExerciseEntry) -> Int {
        (entry.sets.firstIndex { $0.id == setID } ?? 0) + 1
    }

    /// The keypad's "Log set": an open set is completed (with the typed effort, if any) and
    /// starts rest, exactly like ticking it; one that's already done just keeps the edits.
    func logSet(exerciseID: UUID, setID: UUID, effort: Effort?) {
        let entry = session.exercises.first(where: { $0.id == exerciseID })
        let isDone = entry?.sets.first(where: { $0.id == setID })?.isDone ?? false
        if !isDone {
            session.completeSet(exerciseID: exerciseID, setID: setID, effort: effort)
        } else if let effort {
            session.setEffort(exerciseID: exerciseID, setID: setID, effort: effort)
        }
        store.sync(session: session)
    }

    /// Where a keypad binding writes: looked up by id on every get/set, never by the indices
    /// that were current when the sheet opened — a swipe-delete's undo or a Live Activity
    /// mutation can reorder the sets underneath an open keypad.
    struct SetAddress {
        var exerciseID: UUID
        var setID: UUID
    }

    /// Cardio fields type in the display unit (minutes, km/mi, %) and land on the row as
    /// seconds / metres / percent. The "last" line is the target the row was pre-filled with.
    private func cardioKeypad(field: ActiveSheet.KeypadField, set: SetEntry, ids: SetAddress) -> some View {
        let distanceUnit = preferences.distanceUnit
        let spec: CardioKeypadSpec = switch field {
        case .minutes:
            CardioKeypadSpec(
                title: "Time", label: "MIN", step: 1, last: set.targetSeconds.map(CardioPace.clock)
            )
        case .distance:
            CardioKeypadSpec(
                title: "Distance", label: distanceUnit.symbol.uppercased(), step: 0.25,
                last: set.targetDistanceMeters.map { distanceUnit.format(meters: $0) }
            )
        case .incline, .weight, .reps:
            CardioKeypadSpec(title: "Incline", label: "%", step: 0.5, last: nil)
        }
        return WeightKeypadSheet(
            title: spec.title, value: cardioBinding(field: field, ids: ids), step: spec.step, bar: nil,
            last: spec.last, unit: nil, plainLabel: spec.label, onDone: { store.sync(session: session) }
        )
    }

    /// How the keypad is labelled and stepped for one cardio field.
    private struct CardioKeypadSpec {
        var title: String
        var label: String
        var step: Double
        var last: String?
    }

    private func cardioBinding(field: ActiveSheet.KeypadField, ids: SetAddress) -> Binding<Double> {
        let unit = preferences.distanceUnit
        return setBinding(ids, fallback: 0) { set in
            switch field {
            case .minutes: Double(set.cardioSeconds ?? 0) / 60
            case .distance: unit.display(meters: set.cardioMeters ?? 0)
            case .incline, .weight, .reps: set.inclinePercent ?? 0
            }
        } write: { set, value in
            switch field {
            case .minutes: set.durationSeconds = Int((value * 60).rounded())
            case .distance: set.distanceMeters = unit.toMeters(value)
            case .incline, .weight, .reps: set.inclinePercent = value
            }
        }
    }

    private func effortBinding(_ ids: SetAddress) -> Binding<Effort?> {
        setBinding(ids, fallback: nil, read: \.effort) { set, value in set.effort = value }
    }

    private func weightBinding(_ ids: SetAddress) -> Binding<Double> {
        setBinding(ids, fallback: 0, read: \.weightKg) { set, value in set.weightKg = value }
    }

    private func repsBinding(_ ids: SetAddress) -> Binding<Double> {
        // `Int(_:)` traps on a non-finite double; the keypad can't produce one, but a trap is
        // the wrong failure mode for a text field either way.
        setBinding(ids, fallback: 0) { Double($0.reps) } write: { set, value in
            set.reps = value.isFinite ? Int(value) : 0
        }
    }

    /// A binding onto one set, resolved by id at access time. A set that has gone (deleted
    /// while the keypad was up) reads as `fallback` and swallows writes.
    private func setBinding<Value>(
        _ ids: SetAddress, fallback: Value, read: @escaping (SetEntry) -> Value,
        write: @escaping (inout SetEntry, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let entry = session.exercises.first(where: { $0.id == ids.exerciseID }),
                      let set = entry.sets.first(where: { $0.id == ids.setID }) else { return fallback }
                return read(set)
            },
            set: { value in
                guard let ei = session.exercises.firstIndex(where: { $0.id == ids.exerciseID }),
                      let si = session.exercises[ei].sets.firstIndex(where: { $0.id == ids.setID })
                else { return }
                write(&session.exercises[ei].sets[si], value)
            }
        )
    }
}
