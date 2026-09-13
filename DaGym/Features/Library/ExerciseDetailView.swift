import Charts
import GymCore
import SwiftUI

/// Exercise Detail — stats, a 6-month e1RM trend and reference settings
/// for a single exercise.
struct ExerciseDetailView: View {
    var exercise: ExerciseInfo

    @State private var isFavorite: Bool
    @State private var selectedMetric = "1RM"
    @Environment(\.dismiss) private var dismiss

    private static let metrics = ["1RM", "Top Set", "Volume", "Reps"]

    init(exercise: ExerciseInfo) {
        self.exercise = exercise
        _isFavorite = State(initialValue: exercise.isFavorite)
    }

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s5) {
                    topRow
                    titleBlock
                    statTiles
                    ChartCard(selectedMetric: $selectedMetric, metrics: Self.metrics)
                    instructionsCard
                    settingsCard
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .navigationBarHidden(true)
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
            Button {
                isFavorite.toggle()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
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

    private var equipmentLine: String {
        let barName = exercise.bar?.name.lowercased() ?? "bodyweight"
        let increment = WorkoutSession.format(exercise.incrementKg)
        return "\(exercise.equipment) · \(barName) · \(increment) kg increment"
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
            value: exercise.bestE1RM.map(WorkoutSession.format) ?? "—",
            label: "Best E1RM", tint: DGColor.prGoldText
        )
        .dgCard(
            radius: 14, fill: DGColor.prGold.opacity(0.10), stroke: DGColor.prGold.opacity(0.35), padding: 0
        )
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("How To Do It").dgLabel()
            Text(exercise.instructions.isEmpty ? "No instructions yet." : exercise.instructions)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            SettingsRow(label: "Rest timer", value: WorkoutSession.clock(exercise.restSeconds))
            Divider().overlay(DGColor.hairline)
            SettingsRow(label: "Bar type", value: barTypeValue)
            Divider().overlay(DGColor.hairline)
            SettingsRow(label: "Weight increment", value: "\(WorkoutSession.format(exercise.incrementKg)) kg")
        }
        .dgCard(padding: 0)
    }

    private var barTypeValue: String {
        guard let bar = exercise.bar else { return "None" }
        return "\(bar.name) \(WorkoutSession.format(bar.weightKg)) kg"
    }
}

/// Estimated-1RM trend chart with the metric segment toggle.
private struct ChartCard: View {
    @Binding var selectedMetric: String
    var metrics: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            HStack {
                Text("Estimated 1RM · 6 Months").dgLabel()
                Spacer()
                Text("+\(delta) kg")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.success)
            }
            chart
            segmentToggle
        }
        .dgCard()
    }

    private var delta: String {
        guard let first = SampleData.e1rmSeries.first?.value,
              let last = SampleData.e1rmSeries.last?.value else { return "0" }
        return WorkoutSession.format(last - first)
    }

    private var chart: some View {
        Chart(Array(SampleData.e1rmSeries.enumerated()), id: \.offset) { index, point in
            LineMark(x: .value("Month", point.month), y: .value("E1RM", point.value))
                .foregroundStyle(DGColor.coral)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            if index == SampleData.e1rmSeries.count - 1 {
                PointMark(x: .value("Month", point.month), y: .value("E1RM", point.value))
                    .foregroundStyle(DGColor.coral)
                    .symbolSize(64)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(DGFont.label)
                    .foregroundStyle(DGColor.ink3)
            }
        }
        .frame(height: 140)
    }

    private var segmentToggle: some View {
        HStack(spacing: 2) {
            ForEach(metrics, id: \.self) { metric in
                let selected = metric == selectedMetric
                Button {
                    selectedMetric = metric
                } label: {
                    Text(metric)
                        .font(DGFont.condensedLabel(12))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(selected ? DGColor.coralText : DGColor.ink3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DGColor.coralWash)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .dgGlass(.thin, radius: 12)
    }
}

/// One "Label … Value" row in the settings card.
private struct SettingsRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Text(value)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        }
        .padding(.vertical, DGSpace.s3)
        .padding(.horizontal, DGSpace.s5)
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exercise: SampleData.bench)
    }
}
