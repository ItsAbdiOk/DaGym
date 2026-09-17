import GymCore
import SwiftData
import SwiftUI

/// Exercise Detail — the illustration, three stat tiles, an e1RM trend built from real history
/// and a white row group of the exercise's own settings. Pushed from the library, so the name
/// is the inline title and the system back button reads "‹ Library".
struct ExerciseDetailView: View {
    @Environment(WorkoutStore.self) private var store
    // Not private: the display and row pieces live in the `+Layout` and `+Rows` files.
    @Environment(Preferences.self) var preferences
    @Environment(\.dismiss) var dismiss

    @State var exercise: ExerciseInfo
    @State var lastSessions: [String] = []
    @State var restSeconds: Int
    @State var incrementKg: Double
    @State var barTypeKey: String?
    @State var showingCalculator = false
    @State var notes: [ExerciseNoteInfo] = []
    @State var showingAddToRoutine = false
    @State var showingEdit = false
    @State private var confirmingDelete = false
    @State private var routinesUsing: [RoutineInfo] = []

    /// Rest choices; `0` is "Default" — follow Settings → Default rest (and the training goal
    /// that set it) rather than pinning this exercise to its own number.
    static let restOptions = [0, 60, 90, 120, 150, 180, 210, 240, 300]

    /// "Default · 2:30" for the follow-the-setting choice (or "Default · Off"), else the clock.
    static func restLabel(_ seconds: Int, defaultSeconds: Int) -> String {
        guard seconds > 0 else {
            let fallback = defaultSeconds > 0 ? WorkoutSession.clock(defaultSeconds) : "Off"
            return "Default · \(fallback)"
        }
        return WorkoutSession.clock(seconds)
    }

    /// Increment choices in kg, in the lifter's unit: the standard kg microplate steps, or a
    /// lb lifter's own steps (0.5 lb up to a 25 lb jump) converted to kg — offering "5 lb" rather
    /// than kg's 2.5 kg (5.5 lb) rounded through `preferences.formatWeight`.
    static func incrementOptions(for unit: WeightUnit) -> [Double] {
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
                VStack(alignment: .leading, spacing: DGSpace.s3) {
                    heroCard
                    statTiles
                    ExerciseChartView(exerciseID: exercise.id)
                        .dgCard(radius: 20, padding: DGSpace.s4)
                    settingsGroup
                    customActionsGroup
                    ExerciseTextCard(
                        title: "Recent sessions", lines: lastSessions, emptyText: "No sessions logged yet.",
                        tint: DGColor.ink1
                    )
                    ExerciseInstructionsCard(steps: instructionSteps)
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s4)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { favoriteButton }
        }
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

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: exercise.isFavorite ? "star.fill" : "star")
                .foregroundStyle(exercise.isFavorite ? DGColor.prGold : DGColor.coralText)
        }
        .accessibilityLabel(exercise.isFavorite ? "Remove from favourites" : "Add to favourites")
    }

    func refresh() {
        if let model = store.fetchExerciseModel(id: exercise.id) {
            exercise = store.exerciseInfo(for: model)
            restSeconds = model.restSeconds
            incrementKg = model.incrementKg
            barTypeKey = model.barType
        }
        lastSessions = store.lastSessions(exerciseID: exercise.id)
        notes = store.exerciseNotes(exerciseID: exercise.id)
    }

    func deleteNote(_ note: ExerciseNoteInfo) {
        store.deleteExerciseNote(id: note.id)
        refresh()
    }

    func confirmDelete() {
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

    func updateRest(_ seconds: Int) {
        restSeconds = seconds
        persistSettings()
    }

    func updateBar(_ option: BarOption) {
        barTypeKey = option.storeValue
        persistSettings()
    }

    func updateIncrement(_ increment: Double) {
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

/// Edit and Delete for the lifter's own custom exercises, as a row group of their own.
struct ExerciseActionsCard: View {
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DetailRow(label: "Edit exercise", action: onEdit)
            Button(action: onDelete) {
                HStack {
                    Text("Delete exercise")
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.danger)
                    Spacer()
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(DGPressStyle())
        }
        .dgCard(radius: 14, padding: 0)
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
