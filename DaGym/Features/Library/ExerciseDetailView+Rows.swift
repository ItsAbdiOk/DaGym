import GymCore
import SwiftUI

/// The white row group under the chart (the redesign prototype's `exRows`): 1RM calculator ·
/// Rest timer · Bar type · Weight increment · Add to a routine · Notes from workouts. Split
/// from the main file to stay under the type-body-length cap.
extension ExerciseDetailView {
    var settingsGroup: some View {
        VStack(spacing: 0) {
            DetailRow(label: "1RM calculator", value: bestE1RMLabel) { showingCalculator = true }
            MenuSettingsRow(label: "Rest timer", value: restLabel(restSeconds), hairline: true) {
                ForEach(Self.restOptions, id: \.self) { seconds in
                    Button(restLabel(seconds)) { updateRest(seconds) }
                }
            }
            MenuSettingsRow(label: "Bar type", value: BarOption.from(barTypeKey).title, hairline: true) {
                ForEach(BarOption.allCases) { option in
                    Button(option.title) { updateBar(option) }
                }
            }
            MenuSettingsRow(label: "Weight increment", value: incrementLabel(incrementKg), hairline: true) {
                ForEach(Self.incrementOptions(for: preferences.weightUnit), id: \.self) { increment in
                    Button(incrementLabel(increment)) { updateIncrement(increment) }
                }
            }
            DetailRow(label: "Add to a routine") { showingAddToRoutine = true }
            NavigationLink {
                notesScreen
            } label: {
                DetailRowLabel(label: "Notes from workouts", value: "\(notes.count)", isLast: true)
            }
            .buttonStyle(DGPressStyle())
        }
        .dgCard(radius: 14, padding: 0)
    }

    /// The notes row's destination: every note ever left on the exercise, deletable where scoped.
    private var notesScreen: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                ExerciseNotesCard(notes: notes, onDelete: deleteNote)
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s6)
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Edit and delete, for the lifter's own exercises only — a second group under the first.
    @ViewBuilder
    var customActionsGroup: some View {
        if exercise.isCustom {
            ExerciseActionsCard(onEdit: { showingEdit = true }, onDelete: confirmDelete)
        }
    }

    var bestE1RMLabel: String {
        guard let best = exercise.bestE1RM else { return "—" }
        return "\(preferences.formatWeight(kg: best)) \(preferences.unitSymbol)"
    }

    func incrementLabel(_ kg: Double) -> String {
        "\(preferences.formatWeight(kg: kg)) \(preferences.unitSymbol)"
    }

    func restLabel(_ seconds: Int) -> String {
        Self.restLabel(seconds, defaultSeconds: preferences.defaultRestSeconds)
    }
}

/// One tappable "Label … value ›" row of a white row group.
struct DetailRow: View {
    var label: String
    var value: String?
    var isLast = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            DetailRowLabel(label: label, value: value, isLast: isLast)
        }
        .buttonStyle(DGPressStyle())
    }
}

/// The row's face: 15.5 pt label, dim tabular value, a faint chevron and the hairline under
/// it (dropped on the last row so the group's corner stays clean).
struct DetailRowLabel: View {
    var label: String
    var value: String?
    var isLast = false
    var chevron = "chevron.right"

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            Text(label)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            if let value {
                Text(value)
                    .font(DGFont.subhead)
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
            }
            Image(systemName: chevron)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DGColor.ink4)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(minHeight: 46)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(DGColor.hairline).frame(height: 0.5).padding(.leading, 15)
            }
        }
    }
}
