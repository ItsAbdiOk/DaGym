import GymCore
import SwiftUI

/// The past-notes card on `ExerciseDetailView` (features.md adopt 5): every note ever left on
/// the exercise, newest first, with its date and scope; scoped notes can be deleted here.
struct ExerciseNotesCard: View {
    var notes: [ExerciseNoteInfo]
    var onDelete: (ExerciseNoteInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Notes").dgLabel()
            if notes.isEmpty {
                Text("Notes you leave mid-workout show up here.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            } else {
                ForEach(notes) { note in
                    row(note)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }

    private func row(_ note: ExerciseNoteInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DGSpace.s2) {
                Text(Self.dateLabel(note.createdAt))
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                if note.scope != .session {
                    DGTag(text: note.scope.title)
                }
                Spacer()
                if note.scope != .session {
                    Button(role: .destructive) {
                        onDelete(note)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DGColor.ink4)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.dgControl)
                    .accessibilityLabel("Delete note")
                }
            }
            Text(note.text)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// "Add to routine…" (features.md adopt 16): pick a routine to append the exercise to, or
/// start a new one holding just this exercise.
struct AddToRoutineSheet: View {
    var exercise: ExerciseInfo
    var onAdded: (RoutineInfo) -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var routines: [RoutineInfo] = []

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s4) {
                    Text("Add To Routine")
                        .font(DGFont.title2)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                    VStack(spacing: 0) {
                        ForEach(routines) { routine in
                            routineRow(routine)
                            Divider().overlay(DGColor.hairline)
                        }
                        newRoutineRow
                    }
                    .dgCard(padding: 0)
                }
                .padding(DGSpace.s4)
            }
        }
        .task { routines = store.routines() }
        .presentationDetents([.medium, .large])
    }

    private func routineRow(_ routine: RoutineInfo) -> some View {
        let contains = routine.exercises.contains { $0.id == exercise.id }
        return Button {
            store.addExercise(id: exercise.id, toRoutine: routine.id)
            finish(routineID: routine.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                    Text(contains ? "Already in this routine · add again" : subtitle(routine))
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer()
                Image(systemName: "plus.circle").accessibilityHidden(true)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.coralText)
            }
            .padding(.vertical, DGSpace.s3)
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: DGTap.rowHeight)
        }
        .buttonStyle(.dgRow)
    }

    private func subtitle(_ routine: RoutineInfo) -> String {
        routine.exercises.count == 1 ? "1 exercise" : "\(routine.exercises.count) exercises"
    }

    private var newRoutineRow: some View {
        Button {
            let sets = (0..<3).map { _ in PlannedSetDraft.initial(for: exercise.loggingStyle) }
            let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: sets)
            let created = store.saveRoutine(id: nil, name: "\(exercise.name) Day", exercises: [draft])
            finish(routineID: created.id)
        } label: {
            HStack {
                Text("New routine with \(exercise.name)")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.coralText)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.coralText)
            }
            .padding(.vertical, DGSpace.s3)
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: DGTap.rowHeight)
        }
        .buttonStyle(.dgRow)
    }

    private func finish(routineID: UUID) {
        Haptics.setDone()
        if let routine = store.routines().first(where: { $0.id == routineID }) { onAdded(routine) }
        dismiss()
    }
}

/// Edit sheet for a custom exercise (features.md adopt 16): the same fields the New Exercise
/// sheet takes, prefilled, written back through `WorkoutStore.updateCustomExercise`.
struct EditExerciseSheet: View {
    var exercise: ExerciseInfo
    var onSaved: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var muscle: Muscle
    @State private var equipment: EquipmentOption
    @State private var loggingStyle: ExerciseInfo.LoggingStyle
    @State private var isPerSide: Bool
    @State private var barType: BarChoice

    init(exercise: ExerciseInfo, onSaved: @escaping () -> Void) {
        self.exercise = exercise
        self.onSaved = onSaved
        _name = State(initialValue: exercise.name)
        _muscle = State(initialValue: exercise.primary.first ?? .chest)
        _equipment = State(initialValue: EquipmentOption(rawValue: exercise.equipment) ?? .other)
        _loggingStyle = State(initialValue: exercise.loggingStyle)
        _isPerSide = State(initialValue: exercise.isPerSide)
        _barType = State(initialValue: exercise.bar?.name == Bar.womens.name ? .womens : .olympic)
    }

    private var showsBarRow: Bool { equipment == .barbell || equipment == .ezBar }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            AmbientWash()
            VStack(alignment: .leading, spacing: DGSpace.s5) {
                navRow
                formCard
                Spacer()
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.top, DGSpace.s3)
        }
    }

    private var navRow: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink3)
            Spacer()
            Text("Edit Exercise")
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Button("Save", action: save)
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(canSave ? DGColor.coralText : DGColor.ink4)
                .disabled(!canSave)
        }
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Name").dgLabel().frame(minWidth: 90, alignment: .leading)
                TextField("Exercise name", text: $name)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            .padding(.vertical, DGSpace.s3)
            .padding(.horizontal, DGSpace.s5)
            Divider().overlay(DGColor.hairline)
            MenuSettingsRow(label: "Muscle", value: muscle.displayName) {
                ForEach(Muscle.allCases) { option in
                    Button(option.displayName) { muscle = option }
                }
            }
            Divider().overlay(DGColor.hairline)
            MenuSettingsRow(label: "Equipment", value: equipment.title) {
                ForEach(EquipmentOption.allCases) { option in
                    Button(option.title) { equipment = option }
                }
            }
            Divider().overlay(DGColor.hairline)
            MenuSettingsRow(label: "Logging", value: loggingStyle.rawValue) {
                ForEach(ExerciseInfo.LoggingStyle.allCases, id: \.rawValue) { option in
                    Button(option.rawValue) { loggingStyle = option }
                }
            }
            Divider().overlay(DGColor.hairline)
            Toggle("Per side", isOn: $isPerSide)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .tint(DGColor.coral)
                .padding(.vertical, DGSpace.s3)
                .padding(.horizontal, DGSpace.s5)
            if showsBarRow {
                Divider().overlay(DGColor.hairline)
                MenuSettingsRow(label: "Bar", value: barType.title) {
                    ForEach(BarChoice.allCases) { option in
                        Button(option.title) { barType = option }
                    }
                }
            }
        }
        .dgCard(padding: 0)
    }

    private func save() {
        let fields = CustomExerciseFields(
            name: name, primary: [muscle], equipment: equipment.rawValue, style: loggingStyle,
            isPerSide: isPerSide, barType: showsBarRow ? barType.storeValue(for: equipment) : nil
        )
        store.updateCustomExercise(id: exercise.id, fields: fields)
        onSaved()
        dismiss()
    }
}

/// A labelled card of text lines ("Last 3 Sessions", "How To Do It") with an empty-state line.
struct ExerciseTextCard: View {
    var title: String
    var lines: [String]
    var emptyText: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(title).dgLabel()
            if lines.isEmpty {
                Text(emptyText)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(DGFont.body)
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }
}

/// Bar-type options for the settings menu, mapped to `ExerciseModel.barType`.
enum BarOption: String, CaseIterable, Identifiable {
    case none, olympic, womens, ezBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .olympic: "Olympic"
        case .womens: "Women's"
        case .ezBar: "EZ Bar"
        }
    }

    var storeValue: String? { self == .none ? nil : rawValue }

    static func from(_ value: String?) -> BarOption {
        BarOption(rawValue: value ?? "none") ?? .none
    }
}

/// One editable "Label … Value ⌄" row inside the settings card (shared with `EditExerciseSheet`).
struct MenuSettingsRow<Items: View>: View {
    var label: String
    var value: String
    @ViewBuilder var items: Items

    var body: some View {
        Menu {
            items
        } label: {
            HStack {
                Text(label)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Text(value)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
                Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.vertical, DGSpace.s3)
            .padding(.horizontal, DGSpace.s5)
        }
        .buttonStyle(.dgRow)
    }
}
