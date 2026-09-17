import GymCore
import SwiftUI

/// "By exercise", pushed from the Progress hub: one exercise at a time through
/// `ExerciseChartView`, with the exercise picker above the chart and the 1RM calculator in the
/// bar. Named `ProgressScreen` rather than `ProgressView` to avoid shadowing
/// `SwiftUI.ProgressView` throughout the app module. The body-wide charts that used to sit
/// behind a mode toggle here live in This week › Trends now.
struct ProgressScreen: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var exercise: ExerciseInfo?
    @State private var showingPicker = false
    @State private var showingCalculator = false

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s3) {
                    ExercisePickerRow(exercise: exercise) { showingPicker = true }
                    if let exercise {
                        ExerciseChartView(exerciseID: exercise.id)
                            .dgCard(radius: 20, padding: DGSpace.s4)
                    } else {
                        EmptyState(
                            symbol: "dumbbell", title: "Pick an exercise",
                            message: "Choose an exercise to see its progress over time."
                        )
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("By exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("1RM calc") { showingCalculator = true }
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.coralText)
            }
        }
        .task { pickDefaultExercise() }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerSheet { exercise = $0 }
        }
        .sheet(isPresented: $showingCalculator) {
            OneRepMaxCalculatorView(
                weightKg: exercise?.bestE1RM ?? 60, bar: exercise?.bar ?? preferences.weightUnit.defaultBar
            )
        }
    }

    private func pickDefaultExercise() {
        guard exercise == nil else { return }
        // One catalogue (two fetches + the PR table) for both lookups, not one per call.
        let catalogue = store.exerciseCatalogue()
        exercise = store.exercises(in: catalogue, favoritesOnly: true).first
            ?? store.exercises(in: catalogue).first
    }
}

/// "Bench Press ⌄" row that opens `ExercisePickerSheet`.
private struct ExercisePickerRow: View {
    var exercise: ExerciseInfo?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(exercise?.name ?? "Choose exercise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
        .dgCard(radius: 16, padding: 0)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack { ProgressScreen() }
            .environment(store)
            .environment(Preferences())
    }
}
