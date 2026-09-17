import GymCore
import SwiftUI

// The cards `RoutineBuilderView` stacks: the name/muscle-map header, one card per draft
// exercise, and the planned-set row inside it. (`BuilderCardioSetRow` and `AddExerciseButton`
// live in `RoutineBuilderSupport.swift`.)

/// "NAME" card: editable title, plus a live body-map thumbnail and "HITS"
/// summary line that update as exercises are added, removed or swapped.
struct NameCard: View {
    @Binding var name: String
    var hitMap: [Muscle: Double]
    var hitSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Name").dgLabel()
                TextField("Routine name", text: $name)
                    .font(DGFont.title2)
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
struct BuilderExerciseCard: View {
    @Environment(Preferences.self) private var preferences
    @Binding var item: EditableExercise
    var isSuperset: Bool
    var onToggleSuperset: () -> Void
    var onRemove: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    /// Nil hides the drag handle (a one-exercise routine has nothing to reorder).
    var dragProvider: (() -> NSItemProvider)?

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
            if let dragProvider {
                // Touch-and-hold lifts the card; the menu's Move Up / Move Down is the VoiceOver
                // and Switch Control route, so the handle itself is not an element.
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onDrag(dragProvider)
                    .accessibilityHidden(true)
            }
            Text(item.exercise.name)
                .font(DGFont.title3)
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
struct BuilderSetRow: View {
    @Binding var set: PlannedSetDraft

    var body: some View {
        DGAdaptiveStack(spacing: DGSpace.s3) {
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
