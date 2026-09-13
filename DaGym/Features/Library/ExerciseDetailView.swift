import GymCore
import SwiftData
import SwiftUI

/// Exercise Detail — stats, an e1RM trend built from real history and
/// editable reference settings for a single exercise.
struct ExerciseDetailView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var exercise: ExerciseInfo
    @State private var lastSessions: [String] = []
    @State private var restSeconds: Int
    @State private var incrementKg: Double
    @State private var barTypeKey: String?
    @State private var showingCalculator = false
    @State private var notes: [ExerciseNoteInfo] = []
    @State private var showingAddToRoutine = false
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var routinesUsing: [RoutineInfo] = []

    private static let restOptions = [60, 90, 120, 150, 180, 210, 240, 300]

    /// Increment choices in kg, in the lifter's unit: the standard kg microplate steps, or a
    /// lb lifter's own steps (0.5 lb up to a 25 lb jump) converted to kg — offering "5 lb" rather
    /// than kg's 2.5 kg (5.5 lb) rounded through `preferences.formatWeight`.
    private static func incrementOptions(for unit: WeightUnit) -> [Double] {
        switch unit {
        case .kg: return [0.5, 1, 1.25, 2, 2.5, 5, 10]
        case .lb: return [0.5, 1, 2, 2.5, 5, 10, 25].map(unit.toKg)
        }
    }

    init(exercise: ExerciseInfo) {
        _exercise = State(initialValue: exercise)
        _restSeconds = State(initialValue: exercise.restSeconds)
        _incrementKg = State(initialValue: exercise.incrementKg)
    }

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s5) {
                    topRow
                    titleBlock
                    statTiles
                    ExerciseChartView(exerciseID: exercise.id)
                        .dgCard()
                    oneRepMaxRow
                    ExerciseTextCard(
                        title: "Last 3 Sessions", lines: lastSessions, emptyText: "No sessions logged yet.",
                        tint: DGColor.ink1
                    )
                    ExerciseNotesCard(notes: notes, onDelete: deleteNote)
                    ExerciseTextCard(
                        title: "How To Do It", lines: instructionLines, emptyText: "Instructions coming soon",
                        tint: DGColor.ink2
                    )
                    settingsCard
                    ExerciseActionsCard(
                        isCustom: exercise.isCustom, onAddToRoutine: { showingAddToRoutine = true },
                        onEdit: { showingEdit = true }, onDelete: confirmDelete
                    )
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .navigationBarHidden(true)
        .task { refresh() }
        .sheet(isPresented: $showingCalculator) {
            OneRepMaxCalculatorView(
                weightKg: exercise.bestE1RM ?? incrementKg * 20, reps: 5, bar: exercise.bar ?? .olympic
            )
        }
        .sheet(isPresented: $showingAddToRoutine) {
            AddToRoutineSheet(exercise: exercise) { _ in refresh() }
        }
        .sheet(isPresented: $showingEdit) {
            EditExerciseSheet(exercise: exercise, onSaved: refresh)
        }
        .confirmationDialog(
            "Delete \(exercise.name)?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete Exercise", role: .destructive, action: deleteExercise)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ExerciseActionsCard.deleteWarning(routines: routinesUsing))
        }
    }

    private var instructionLines: [String] {
        exercise.instructions.isEmpty ? [] : [exercise.instructions]
    }

    private var oneRepMaxRow: some View {
        Button {
            showingCalculator = true
        } label: {
            HStack {
                Image(systemName: "function")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DGColor.prGoldText)
                Text("1RM Calculator")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: DGTap.min)
            .dgCard(padding: 0)
        }
        .buttonStyle(DGPressStyle())
    }

    private var topRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: DGSpace.s1) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Library").dgLabel()
                }
                .foregroundStyle(DGColor.ink3)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: toggleFavorite) {
                Image(systemName: exercise.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.prGoldText)
                    .frame(width: 36, height: 36)
                    .dgGlass(.regular, in: Circle())
            }
            .buttonStyle(DGPressStyle())
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            HStack(alignment: .top) {
                Text(exercise.name)
                    .font(DGFont.title1)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(2)
                Spacer()
                BodyMapPair(intensity: exercise.hitMap, height: 56)
            }
            Text(equipmentLine)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    /// "barbell · olympic bar · 2.5 kg increment"; a bodyweight move has no bar and no
    /// increment worth stating, so it reads just "bodyweight".
    private var equipmentLine: String {
        var parts = [exercise.equipment]
        if let bar = exercise.bar { parts.append(bar.name.lowercased()) }
        if exercise.incrementKg > 0 {
            let increment = preferences.formatWeight(kg: exercise.incrementKg)
            parts.append("\(increment) \(preferences.unitSymbol) increment")
        }
        return parts.joined(separator: " · ")
    }

    private var statTiles: some View {
        HStack(spacing: DGSpace.s3) {
            goldStat
            StatTile(value: exercise.bestSet ?? "—", label: "Best Set")
                .dgCard(radius: 14, padding: 0)
            StatTile(value: "\(exercise.sessions)", label: "Sessions")
                .dgCard(radius: 14, padding: 0)
        }
    }

    private var goldStat: some View {
        StatTile(
            value: exercise.bestE1RM.map { preferences.formatWeight(kg: $0) } ?? "—",
            label: "Best E1RM", tint: DGColor.prGoldText
        )
        .dgCard(
            radius: 14, fill: DGColor.prGold.opacity(0.10), stroke: DGColor.prGold.opacity(0.35), padding: 0
        )
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            MenuSettingsRow(label: "Rest timer", value: WorkoutSession.clock(restSeconds)) {
                ForEach(Self.restOptions, id: \.self) { seconds in
                    Button(WorkoutSession.clock(seconds)) { updateRest(seconds) }
                }
            }
            Divider().overlay(DGColor.hairline)
            MenuSettingsRow(label: "Bar type", value: BarOption.from(barTypeKey).title) {
                ForEach(BarOption.allCases) { option in
                    Button(option.title) { updateBar(option) }
                }
            }
            Divider().overlay(DGColor.hairline)
            MenuSettingsRow(
                label: "Weight increment",
                value: "\(preferences.formatWeight(kg: incrementKg)) \(preferences.unitSymbol)"
            ) {
                ForEach(Self.incrementOptions(for: preferences.weightUnit), id: \.self) { increment in
                    Button("\(preferences.formatWeight(kg: increment)) \(preferences.unitSymbol)") {
                        updateIncrement(increment)
                    }
                }
            }
        }
        .dgCard(padding: 0)
    }

    private func refresh() {
        if let model = store.fetchExerciseModel(id: exercise.id) {
            exercise = store.exerciseInfo(for: model)
            restSeconds = model.restSeconds
            incrementKg = model.incrementKg
            barTypeKey = model.barType
        }
        lastSessions = store.lastSessions(exerciseID: exercise.id)
        notes = store.exerciseNotes(exerciseID: exercise.id)
    }

    private func deleteNote(_ note: ExerciseNoteInfo) {
        store.deleteExerciseNote(id: note.id)
        refresh()
    }

    private func confirmDelete() {
        routinesUsing = store.routinesUsing(exerciseID: exercise.id)
        confirmingDelete = true
    }

    private func deleteExercise() {
        guard store.deleteCustomExercise(id: exercise.id) else { return }
        dismiss()
    }

    private func toggleFavorite() {
        store.toggleFavorite(id: exercise.id)
        refresh()
    }

    private func updateRest(_ seconds: Int) {
        restSeconds = seconds
        persistSettings()
    }

    private func updateBar(_ option: BarOption) {
        barTypeKey = option.storeValue
        persistSettings()
    }

    private func updateIncrement(_ increment: Double) {
        incrementKg = increment
        persistSettings()
    }

    private func persistSettings() {
        store.updateExerciseSettings(
            id: exercise.id, restSeconds: restSeconds, barType: barTypeKey, incrementKg: incrementKg
        )
        refresh()
    }
}

/// "Add to routine…" for every exercise; Edit/Delete only for the lifter's own custom ones.
struct ExerciseActionsCard: View {
    var isCustom: Bool
    var onAddToRoutine: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(
                title: "Add to routine…", symbol: "plus.circle", tint: DGColor.coralText,
                action: onAddToRoutine
            )
            if isCustom {
                Divider().overlay(DGColor.hairline)
                row(title: "Edit exercise", symbol: "pencil", tint: DGColor.ink1, action: onEdit)
                Divider().overlay(DGColor.hairline)
                row(title: "Delete exercise", symbol: "trash", tint: DGColor.danger, action: onDelete)
            }
        }
        .dgCard(padding: 0)
    }

    private func row(title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(DGFont.body)
                    .foregroundStyle(tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: DGTap.min)
        }
        .buttonStyle(.plain)
    }

    /// The delete confirmation's message: how many routines lose the exercise.
    static func deleteWarning(routines: [RoutineInfo]) -> String {
        let base = "Past workouts keep their sets."
        switch routines.count {
        case 0: return base
        case 1: return "Used in 1 routine — it'll be removed from \(routines[0].name). \(base)"
        default: return "Used in \(routines.count) routines — it'll be removed from all of them. \(base)"
        }
    }
}

/// A labelled card of text lines ("Last 3 Sessions", "How To Do It") with an empty-state line.
private struct ExerciseTextCard: View {
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
private enum BarOption: String, CaseIterable, Identifiable {
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
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.vertical, DGSpace.s3)
            .padding(.horizontal, DGSpace.s5)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            ExerciseDetailView(exercise: SampleData.bench)
        }
            .environment(store)
            .environment(Preferences())
    }
}
