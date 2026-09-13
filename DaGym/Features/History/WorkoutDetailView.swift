import GymCore
import SwiftData
import SwiftUI

/// Read-only detail for one finished workout: title, time range, stats and
/// a card per exercise with its logged sets.
struct WorkoutDetailView: View {
    var workoutID: UUID

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var detail: WorkoutDetail?

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                if let detail {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        topRow
                        titleBlock(detail)
                        statRow(detail)
                        ForEach(detail.exercises) { entry in ExerciseEntryCard(entry: entry) }
                        if !detail.notes.isEmpty { notesCard(detail) }
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .task { detail = store.workoutDetail(id: workoutID) }
    }

    private var topRow: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: DGSpace.s1) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("History").dgLabel()
            }
            .foregroundStyle(DGColor.ink3)
        }
        .buttonStyle(.plain)
    }

    private func titleBlock(_ detail: WorkoutDetail) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            HStack {
                Text(detail.title)
                    .font(DGFont.title1)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                if detail.isBackfilled {
                    DGTag(text: "Backfilled", tint: DGColor.infoText, wash: DGColor.info.opacity(0.16))
                }
            }
            Text(Self.dateRangeLine(detail))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    private func statRow(_ detail: WorkoutDetail) -> some View {
        HStack(spacing: DGSpace.s3) {
            StatTile(value: "\(detail.durationMinutes)", label: "Minutes").dgCard(radius: 14)
            StatTile(value: WorkoutSession.format(detail.volumeKg), label: "Volume").dgCard(radius: 14)
            StatTile(value: "\(detail.setsDone)", label: "Sets").dgCard(radius: 14)
            StatTile(value: "\(detail.prCount)", label: "PRs", tint: DGColor.prGoldText).dgCard(radius: 14)
        }
    }

    private func notesCard(_ detail: WorkoutDetail) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Notes").dgLabel()
            Text(detail.notes)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }

    private static func dateRangeLine(_ detail: WorkoutDetail) -> String {
        let day = DateFormatter()
        day.dateFormat = "EEEE"
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let dayText = day.string(from: detail.startedAt).uppercased()
        let start = time.string(from: detail.startedAt)
        guard let endedAt = detail.endedAt else { return "\(dayText) · \(start)" }
        return "\(dayText) · \(start)–\(time.string(from: endedAt))"
    }
}

/// One exercise's read-only set list, matching the active-workout set row look.
private struct ExerciseEntryCard: View {
    var entry: WorkoutExerciseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack {
                Text(entry.exercise.name)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Text("\(entry.sets.count) sets").dgLabel()
            }
            VStack(spacing: DGSpace.s2) {
                ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                    ReadOnlySetRow(set: set, index: index + 1)
                }
            }
        }
        .dgCard()
    }
}

/// One read-only "badge · weight × reps · effort" row.
private struct ReadOnlySetRow: View {
    var set: SetEntry
    var index: Int

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            SetKindBadge(kind: set.kind, index: index)
            Text("\(WorkoutSession.format(set.weightKg)) × \(set.reps)")
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            if let effort = set.effort {
                Text(effort.displayValue(scale: .rpe))
                    .font(DGFont.footnote)
                    .foregroundStyle(effort.color)
                    .padding(.horizontal, DGSpace.s2)
                    .frame(height: 24)
                    .background(effort.color.opacity(0.16), in: Capsule())
            }
        }
        .frame(height: 44)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            WorkoutDetailView(workoutID: UUID())
        }
            .environment(store)
    }
}
