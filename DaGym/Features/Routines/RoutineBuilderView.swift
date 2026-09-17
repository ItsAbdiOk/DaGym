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
    /// The card being dragged by its handle; `DraftDropDelegate` reorders as it crosses others.
    @State private var draggingID: UUID?
    @State private var symbolName = "dumbbell"
    @State private var tint = RoutineTint.coral.rawValue
    @State private var ruleState = RuleState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // One `RoutineMuscles.hitMap` per render; the card, its animation and the summary line
        // each used to fold every draft exercise again.
        let hitMap = hitMap
        return ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    navRow
                    NameCard(
                        name: $name, hitMap: hitMap,
                        hitSummary: GymCore.RoutineMuscles.summary(hitMap: hitMap)
                    )
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
                            onMoveDown: { move(id: item.id, up: false) },
                            dragProvider: items.count > 1 ? { beginDrag(id: item.id) } : nil
                        )
                        .opacity(draggingID == item.id ? 0.4 : 1)
                        .onDrop(
                            of: [.text],
                            delegate: DraftDropDelegate(
                                targetID: item.id, items: $items, draggingID: $draggingID,
                                reduceMotion: reduceMotion
                            )
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
            // A card let go between cards, or over the header, still ends its lift.
            .onDrop(of: [.text], isTargeted: nil) { _ in
                draggingID = nil
                return true
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
                Image(systemName: "arrow.up.arrow.down").accessibilityHidden(true)
                    .font(.system(size: 13, weight: .semibold))
                Text("Reorder")
                    .font(DGFont.condensedLabel(14))
            }
            .foregroundStyle(DGColor.ink2)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
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
                .foregroundStyle(DGColor.ink1)
            Spacer()
            if let routineID {
                ShareRoutineButton(title: name) { includeWeights in
                    PlanShareService.exportRoutine(
                        id: routineID, context: store.context, includeWeights: includeWeights
                    )
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
        items = RoutineReorder.step(items, groups: items.map(\.supersetGroup), index: index, up: up)
    }

    /// The handle's long-press lift: remembers which card is moving (the drop delegate reads
    /// it — the item provider's payload is never round-tripped) and hands SwiftUI a provider.
    private func beginDrag(id: UUID) -> NSItemProvider {
        draggingID = id
        return NSItemProvider(object: id.uuidString as NSString)
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

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        RoutineBuilderView(routineID: nil, onDone: {})
            .environment(WorkoutStore(context: container.mainContext))
    } else {
        Text("Preview unavailable")
    }
}
