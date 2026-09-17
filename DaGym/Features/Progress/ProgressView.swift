import GymCore
import SwiftUI

/// The full Progress screen (plan.md §6.4): EXERCISE mode drives `ExerciseChartView` for one
/// exercise at a time, BODY-WIDE mode shows the same weekly-volume/sets-per-muscle cards as
/// `ProgressChartsSection`. Named `ProgressScreen` rather than `ProgressView` to avoid shadowing
/// `SwiftUI.ProgressView` throughout the app module.
struct ProgressScreen: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var mode = Mode.exercise
    @State private var exercise: ExerciseInfo?
    @State private var showingPicker = false
    @State private var showingCalculator = false
    @State private var bundle: WorkoutStore.BodySeriesBundle?

    enum Mode: CaseIterable {
        case exercise, bodyWide
        var title: String { self == .exercise ? "Exercise" : "Body-Wide" }
    }

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s5) {
                    header
                    ModeToggle(mode: $mode)
                    switch mode {
                    case .exercise: exerciseContent
                    case .bodyWide: bodyWideContent
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { refreshBodyWide() }
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

    private var header: some View {
        DGAdaptiveStack(verticalAlignment: .center) {
            Text("Progress")
                .font(DGFont.title1)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            HStack(spacing: DGSpace.s3) {
                Button("1RM Calc") { showingCalculator = true }
                    .buttonStyle(.dgControl)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.coralText)
                DGIconButton(symbol: "xmark", size: 36, accessibilityLabel: "Close") { dismiss() }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var exerciseContent: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            ExercisePickerRow(exercise: exercise) { showingPicker = true }
            if let exercise {
                ExerciseChartView(exerciseID: exercise.id)
                    .dgCard()
            } else {
                EmptyState(
                    symbol: "dumbbell", title: "Pick An Exercise",
                    message: "Choose an exercise to see its progress over time."
                )
            }
        }
    }

    private var bodyWideContent: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            if let bundle, !bundle.weeklyVolume.isEmpty {
                ThisWeekStrip(thisWeek: bundle.thisWeek, lastWeek: bundle.lastWeek)
                WeeklyVolumeCard(weeks: bundle.weeklyVolume)
                SetsPerMuscleCard(setsPerMuscle: bundle.setsPerMuscle)
            } else {
                EmptyState(
                    symbol: "chart.bar",
                    title: "No Progress Yet",
                    message: "Finish a workout to start seeing charts here."
                )
            }
        }
    }

    private func refreshBodyWide() {
        bundle = store.bodySeries(weeks: 8, calendar: preferences.trainingCalendar)
    }

    private func pickDefaultExercise() {
        guard exercise == nil else { return }
        // One catalogue (two fetches + the PR table) for both lookups, not one per call.
        let catalogue = store.exerciseCatalogue()
        exercise = store.exercises(in: catalogue, favoritesOnly: true).first
            ?? store.exercises(in: catalogue).first
    }
}

/// "EXERCISE / BODY-WIDE" segmented toggle, coral when selected.
private struct ModeToggle: View {
    @Binding var mode: ProgressScreen.Mode

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            ForEach(ProgressScreen.Mode.allCases, id: \.title) { option in
                DGChip(title: option.title, selected: option == mode) { mode = option }
            }
        }
    }
}

/// "Bench Press ⌄" row that opens `ExercisePickerSheet`.
private struct ExercisePickerRow: View {
    var exercise: ExerciseInfo?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(exercise?.name ?? "Choose Exercise")
                    .font(DGFont.title3)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: DGTap.min)
            .dgGlass(.thin, radius: DGRadius.md)
        }
        .buttonStyle(.dgControl)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        ProgressScreen()
            .environment(store)
            .environment(Preferences())
    }
}
