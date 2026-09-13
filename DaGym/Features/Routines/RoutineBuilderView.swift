import GymCore
import SwiftData
import SwiftUI

/// One exercise slot as edited on screen; `id` is independent of the
/// exercise's own id so the same exercise could in principle appear twice.
private struct EditableExercise: Identifiable {
    let id = UUID()
    var exercise: ExerciseInfo
    var sets: [PlannedSetDraft]
    var supersetGroup: Int?
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
    @State private var name = "New Routine"
    @State private var items: [EditableExercise] = []
    @State private var showingPicker = false
    @State private var ruleState = RuleState()

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    navRow
                    NameCard(name: $name, hitMap: hitMap, hitSummary: hitSummary)
                        .animation(DGMotion.standard, value: hitMap)
                    ProgressionRulePickerView(title: "Progression", state: $ruleState).dgCard()
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
    }

    private var navRow: some View {
        HStack {
            Button("Cancel", action: onDone)
                .buttonStyle(.plain)
                .dgLabel()
            Spacer()
            Text(routineID == nil ? "New Routine" : "Edit Routine")
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Button("Save", action: save)
                .buttonStyle(.plain)
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
        let rule = store.fetchRoutineModel(id: routineID)?.progressionRuleValue
        ruleState = RuleState.from(rule ?? .doubleProgression(low: 6, high: 8, incrementKg: 2.5))
        items = zip(result.info.exercises, result.drafts).map { info, draft in
            EditableExercise(
                exercise: info, sets: draft.sets, supersetGroup: draft.supersetGroup,
                overrideEnabled: draft.overrideRule != nil,
                overrideState: RuleState.from(draft.overrideRule ?? ruleState.rule),
                excludeFromProgression: draft.excludeFromProgression
            )
        }
    }

    // MARK: - Editing

    private func addExercise(_ exercise: ExerciseInfo) {
        items.append(
            EditableExercise(exercise: exercise, sets: [PlannedSetDraft(kind: .working, targetReps: 8)])
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
                exerciseID: item.exercise.id, supersetGroup: item.supersetGroup, sets: item.sets,
                overrideRule: item.overrideEnabled ? item.overrideState.rule : nil,
                excludeFromProgression: item.excludeFromProgression
            )
        }
        store.saveRoutine(id: routineID, name: name, rule: ruleState.rule, exercises: drafts)
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
                    BuilderSetRow(set: $item.sets[index])
                }
            }
            setsCountStepper
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
            .buttonStyle(.plain)
            Menu {
                Button("Move Up", systemImage: "arrow.up", action: onMoveUp)
                Button("Move Down", systemImage: "arrow.down", action: onMoveDown)
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.ink3)
            }
        }
    }

    private var setsCountStepper: some View {
        Stepper(value: setsCountBinding, in: 1...8) {
            Text("\(item.sets.count) sets").font(DGFont.footnote).foregroundStyle(DGColor.ink3)
        }
    }

    /// Per-exercise progression override + exclude toggles (plan.md §6.5).
    private var progressionOverride: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Toggle("Override progression", isOn: $item.overrideEnabled)
                .font(DGFont.footnote)
                .tint(DGColor.coral)
            if item.overrideEnabled {
                ProgressionRulePickerView(title: "Override", state: $item.overrideState)
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
                    let template = item.sets.last ?? PlannedSetDraft(kind: .working, targetReps: 8)
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

    private var repsBinding: Binding<Int> {
        Binding(get: { set.targetReps ?? 8 }, set: { set.targetReps = $0 })
    }
}

/// Dashed-outline "add exercise" affordance.
private struct AddExerciseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DGSpace.s2) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                Text("Add Exercise")
                    .font(DGFont.condensedLabel(14))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(DGColor.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .dgGlass(.thin, radius: DGRadius.lg)
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                    .strokeBorder(DGColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(DGPressStyle())
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
