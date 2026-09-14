import GymCore
import SwiftData
import SwiftUI

/// Exercise Detail — stats, an e1RM trend built from real history and
/// editable reference settings for a single exercise.
struct ExerciseDetailView: View {
    @Environment(WorkoutStore.self) private var store
    // Not private: the display-only computed properties live in ExerciseDetailView+Layout.swift.
    @Environment(Preferences.self) var preferences
    @Environment(\.dismiss) var dismiss

    @State var exercise: ExerciseInfo
    @State private var lastSessions: [String] = []
    @State private var restSeconds: Int
    @State private var incrementKg: Double
    @State private var barTypeKey: String?
    @State var showingCalculator = false
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
                    heroArt
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

    func toggleFavorite() {
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
        .buttonStyle(.dgRow)
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

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            ExerciseDetailView(exercise: SampleData.bench)
        }
            .environment(store)
            .environment(Preferences())
    }
}
