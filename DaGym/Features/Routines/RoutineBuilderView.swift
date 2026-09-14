import GymCore
import SwiftData
import SwiftUI

/// One exercise slot as edited on screen; `id` is independent of the
/// exercise's own id so the same exercise could in principle appear twice.
struct EditableExercise: Identifiable {
    let id = UUID()
    var exercise: ExerciseInfo
    var sets: [PlannedSetDraft]
    var supersetGroup: Int?
    /// Free-text loading cue ("start at 60 kg, +2.5 when 3×8") shown on the card in a workout.
    var note = ""
    /// Per-exercise progression override (plan.md §6.5): `overrideEnabled` gates whether
    /// `overrideState.rule` is saved, so turning it off cleanly falls back to the routine's rule.
    var overrideEnabled = false
    var overrideState = RuleState()
    var excludeFromProgression = false
}

/// Routine Builder — editable name, a reorderable list of exercises with
/// inline set editing, and superset linking. Glass cards, violet superset
/// tag, coral "add exercise" affordance — see mockup 03_02 (right).
struct RoutineBuilderView: View {
    var routineID: UUID?
    var onDone: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var name = "New Routine"
    @State private var items: [EditableExercise] = []
    @State private var showingPicker = false
    @State private var showingReorder = false
    @State private var symbolName = "dumbbell"
    @State private var tint = RoutineTint.coral.rawValue
    @State private var ruleState = RuleState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    navRow
                    NameCard(name: $name, hitMap: hitMap, hitSummary: hitSummary)
                        .animation(
                            DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion), value: hitMap
                        )
                    GlyphCard(symbolName: $symbolName, tint: $tint)
                    ProgressionRulePickerView(
                        title: "Progression", state: $ruleState, unit: preferences.weightUnit
                    )
                    .dgCard()
                    ForEach($items) { $item in
                        BuilderExerciseCard(
                            item: $item, isSuperset: item.supersetGroup != nil,
                            onToggleSuperset: { toggleSuperset(id: item.id) },
                            onRemove: { remove(id: item.id) },
                            onMoveUp: { move(id: item.id, up: true) },
                            onMoveDown: { move(id: item.id, up: false) }
                        )
                    }
                    AddExerciseButton { showingPicker = true }
                    if items.count > 1 {
                        reorderButton
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .task { load() }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerSheet(onPick: addExercise)
        }
        .sheet(isPresented: $showingReorder) {
            ReorderDraftSheet(items: $items, onDone: { showingReorder = false })
        }
    }

    private var reorderButton: some View {
        Button { showingReorder = true } label: {
            HStack(spacing: DGSpace.s2) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13, weight: .semibold))
                Text("Reorder")
                    .font(DGFont.condensedLabel(14))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(DGColor.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .dgGlass(.thin, radius: DGRadius.lg)
        }
        .buttonStyle(.dgCard)
    }

    private var navRow: some View {
        HStack {
            Button("Cancel", action: onDone)
                .buttonStyle(.dgControl)
                .dgLabel()
            Spacer()
            Text(routineID == nil ? "New Routine" : "Edit Routine")
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            if let routineID {
                ShareRoutineButton(title: name) {
                    PlanShareService.exportRoutine(id: routineID, context: store.context)
                }
            }
            Button("Save", action: save)
                .buttonStyle(.dgControl)
                .dgLabel(DGColor.coralText)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// Live "muscles hit" map, recomputed from the current draft exercises.
    private var hitMap: [Muscle: Double] {
        let entries = items.map {
            (primary: $0.exercise.primary, secondary: $0.exercise.secondary, setCount: $0.sets.count)
        }
        return GymCore.RoutineMuscles.hitMap(exercises: entries)
    }

    private var hitSummary: String { GymCore.RoutineMuscles.summary(hitMap: hitMap) }

    // MARK: - Loading

    private func load() {
        guard let routineID, let result = store.routineDrafts(id: routineID) else { return }
        name = result.info.name
        symbolName = result.info.symbolName
        tint = result.info.tint
        let rule = store.fetchRoutineModel(id: routineID)?.progressionRuleValue
        ruleState = RuleState.from(rule ?? .doubleProgression(low: 6, high: 8, incrementKg: 2.5))
        items = zip(result.info.exercises, result.drafts).map { info, draft in
            EditableExercise(
                exercise: info, sets: draft.sets, supersetGroup: draft.supersetGroup, note: draft.note,
                overrideEnabled: draft.overrideRule != nil,
                overrideState: draft.overrideRule.map(RuleState.from) ?? RuleState.exerciseOverride(
                    of: ruleState.rule, for: info, unit: preferences.weightUnit
                ),
                excludeFromProgression: draft.excludeFromProgression
            )
        }
    }

    // MARK: - Editing

    private func addExercise(_ exercise: ExerciseInfo) {
        items.append(
            EditableExercise(
                exercise: exercise, sets: [PlannedSetDraft.initial(for: exercise.loggingStyle)],
                overrideState: RuleState.exerciseOverride(
                    of: ruleState.rule, for: exercise, unit: preferences.weightUnit
                )
            )
        )
    }

    private func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    private func move(id: UUID, up: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }

    /// Assigns this exercise and the one before it the same superset group
    /// (creating a new group if neither has one yet), or clears both.
    private func toggleSuperset(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let previousIndex = index - 1
        let linkedToPrevious = items[index].supersetGroup != nil
            && items[index].supersetGroup == items[previousIndex].supersetGroup
        if linkedToPrevious {
            items[index].supersetGroup = nil
            let stillLinked = items.indices.contains(index + 1)
                && items[index + 1].supersetGroup == items[previousIndex].supersetGroup
            if !stillLinked { items[previousIndex].supersetGroup = nil }
        } else {
            let group = (items.compactMap(\.supersetGroup).max() ?? 0) + 1
            items[previousIndex].supersetGroup = group
            items[index].supersetGroup = group
        }
    }

    private func save() {
        let drafts = items.map { item in
            RoutineExerciseDraft(
                exerciseID: item.exercise.id, supersetGroup: item.supersetGroup,
                note: item.note.trimmingCharacters(in: .whitespacesAndNewlines), sets: item.sets,
                overrideRule: item.overrideEnabled ? item.overrideState.rule : nil,
                excludeFromProgression: item.excludeFromProgression
            )
        }
        store.saveRoutine(
            id: routineID, name: name, rule: ruleState.rule, symbolName: symbolName, tint: tint,
            exercises: drafts
        )
        onDone()
    }
}

/// "NAME" card: editable title, plus a live body-map thumbnail and "HITS"
/// summary line that update as exercises are added, removed or swapped.
private struct NameCard: View {
    @Binding var name: String
    var hitMap: [Muscle: Double]
    var hitSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Name").dgLabel()
                TextField("Routine name", text: $name)
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                    .textFieldStyle(.plain)
            }
            HStack(spacing: DGSpace.s3) {
                BodyMapPair(intensity: hitMap, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hits").dgLabel()
                    Text(hitSummary)
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink2)
                }
            }
        }
        .dgCard()
    }
}

/// One exercise card: name, move/superset/remove controls, and its set rows.
private struct BuilderExerciseCard: View {
    @Environment(Preferences.self) private var preferences
    @Binding var item: EditableExercise
    var isSuperset: Bool
    var onToggleSuperset: () -> Void
    var onRemove: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            header
            if isSuperset {
                Text("Superset").dgLabel(DGColor.aiVioletText)
            }
            VStack(spacing: DGSpace.s2) {
                ForEach(item.sets.indices, id: \.self) { index in
                    if item.exercise.loggingStyle == .cardio {
                        BuilderCardioSetRow(set: $item.sets[index])
                    } else {
                        BuilderSetRow(set: $item.sets[index])
                    }
                }
            }
            setsCountStepper
            setStyleToggles
            noteField
            progressionOverride
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSuperset ? DGColor.aiViolet.opacity(0.08) : DGColor.surface1,
            in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(isSuperset ? DGColor.aiViolet.opacity(0.4) : DGColor.hairline, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: DGSpace.s3) {
            Text(item.exercise.name)
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Button(action: onToggleSuperset) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSuperset ? DGColor.aiVioletText : DGColor.ink3)
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel(isSuperset ? "Remove from superset" : "Link into superset")
            Menu {
                Button("Move Up", systemImage: "arrow.up", action: onMoveUp)
                Button("Move Down", systemImage: "arrow.down", action: onMoveDown)
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.ink3)
            }
            .accessibilityLabel("More options for \(item.exercise.name)")
        }
    }

    private var setsCountStepper: some View {
        Stepper(value: setsCountBinding, in: 1...8) {
            Text("\(item.sets.count) sets").font(DGFont.footnote).foregroundStyle(DGColor.ink3)
        }
    }

    /// "Every set is a drop set / rest-pause": stamps the kind on every planned set (adding
    /// sets later copies the last one, so the choice sticks). Turning one off returns the sets
    /// to working sets. Mixed kinds picked row-by-row leave both toggles off.
    private var setStyleToggles: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Toggle("Every set is a drop set", isOn: allSetsBinding(.drop))
                .font(DGFont.footnote)
                .tint(DGColor.setDrop)
            Toggle("Every set is rest-pause", isOn: allSetsBinding(.restPause))
                .font(DGFont.footnote)
                .tint(DGColor.setRestPause)
        }
    }

    private func allSetsBinding(_ kind: SetKind) -> Binding<Bool> {
        Binding(
            get: { item.sets.uniformKind == kind },
            set: { on in item.sets.setAllKinds(on ? kind : .working) }
        )
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Loading note").dgLabel()
            TextField("e.g. Start at 60 kg, add 2.5 once 3×8 feels easy", text: $item.note, axis: .vertical)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, DGSpace.s3)
                .padding(.vertical, DGSpace.s2)
                .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Loading note for \(item.exercise.name)")
        }
    }

    /// Per-exercise progression override + exclude toggles (plan.md §6.5).
    private var progressionOverride: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Toggle("Override progression", isOn: $item.overrideEnabled)
                .font(DGFont.footnote)
                .tint(DGColor.coral)
            if item.overrideEnabled {
                ProgressionRulePickerView(
                    title: "Override", state: $item.overrideState, unit: preferences.weightUnit
                )
            }
            Toggle("Exclude from progression", isOn: $item.excludeFromProgression)
                .font(DGFont.footnote)
                .tint(DGColor.coral)
        }
        .padding(.top, DGSpace.s2)
    }

    private var setsCountBinding: Binding<Int> {
        Binding(
            get: { item.sets.count },
            set: { newCount in
                if newCount > item.sets.count {
                    let template = item.sets.last ?? PlannedSetDraft.initial(for: item.exercise.loggingStyle)
                    let added = newCount - item.sets.count
                    item.sets.append(contentsOf: Array(repeating: template, count: added))
                } else if newCount < item.sets.count, newCount >= 1 {
                    item.sets.removeLast(item.sets.count - newCount)
                }
            }
        )
    }
}

/// One planned-set row: a kind tag (tap for a menu of every `SetKind`) and a
/// reps stepper, showing a rep range once a high end is set.
private struct BuilderSetRow: View {
    @Binding var set: PlannedSetDraft

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            kindMenu
            Stepper(value: repsBinding, in: 1...30) {
                Text(repsLabel).font(DGFont.body).foregroundStyle(DGColor.ink1)
            }
        }
    }

    private var kindMenu: some View {
        Menu {
            ForEach(SetKind.allCases, id: \.self) { kind in
                Button(kind.displayName) { set.kind = kind }
            }
        } label: {
            DGTag(text: set.kind.displayName, tint: DGColor.ink2, wash: set.kind.color.opacity(0.22))
        }
    }

    private var repsLabel: String {
        if let high = set.targetRepsHigh, high != set.targetReps {
            return "\(set.targetReps ?? 0)–\(high) reps"
        }
        return "\(set.targetReps ?? 0) reps"
    }

    /// Steps the low end of the range; a high end below it is dragged up so "10–8" can't appear.
    private var repsBinding: Binding<Int> {
        Binding(
            get: { set.targetReps ?? 8 },
            set: { reps in
                set.targetReps = reps
                if let high = set.targetRepsHigh, high < reps { set.targetRepsHigh = reps }
            }
        )
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        RoutineBuilderView(routineID: nil, onDone: {})
            .environment(WorkoutStore(context: container.mainContext))
    } else {
        Text("Preview unavailable")
    }
}
