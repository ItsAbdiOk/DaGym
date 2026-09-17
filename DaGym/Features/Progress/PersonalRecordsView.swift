import SwiftData
import SwiftUI

/// Every cached personal record as a white row group — "Estimated 1RM · Bench Press / 96 kg /
/// 12 Sep" — followed by the milestones card. Lives in This week › Records; `PersonalRecordsView`
/// below is the same section as a screen of its own.
struct RecordsSection: View {
    var generation = 0

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var groups: [ExerciseRecords] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            if groups.isEmpty {
                EmptyState(
                    symbol: "star",
                    title: "No records yet",
                    message: "Finish a workout and your best lifts will show up here."
                )
            } else {
                TrainRowGroup {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                        RecordRow(row: row, isLast: offset == rows.count - 1)
                    }
                }
            }
            MilestonesCard(generation: generation)
        }
        .task(id: generation) { groups = store.personalRecords(unit: preferences.weightUnit) }
    }

    /// One row per record line, exercise by exercise (the store already sorts both).
    private var rows: [RecordRowModel] {
        groups.flatMap { group in
            group.records.map { record in
                RecordRowModel(
                    id: record.id, exerciseID: group.id, title: "\(record.kindLabel) · \(group.exerciseName)",
                    value: record.line, date: record.date
                )
            }
        }
    }
}

private struct RecordRowModel: Identifiable {
    var id: UUID
    var exerciseID: UUID
    var title: String
    var value: String
    var date: Date
}

/// A single record row: kind and exercise, the date underneath, the value on the right — a
/// door to the exercise it belongs to.
private struct RecordRow: View {
    var row: RecordRowModel
    var isLast: Bool

    var body: some View {
        NavigationLink(value: ScreenDestination.exercise(row.exerciseID)) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 15))
                        .foregroundStyle(DGColor.ink1)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(Self.dateLabel(row.date))
                        .font(.system(size: 12))
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer(minLength: 0)
                Text(row.value)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                TrainChevron()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .trainRowDivider(isLast: isLast)
        }
        .buttonStyle(.dgRow)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the exercise")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static func dateLabel(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

/// Records as a pushed screen of its own (the App Store screenshot list still opens it).
struct PersonalRecordsView: View {
    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                RecordsSection()
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s8)
            }
        }
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        NavigationStack { PersonalRecordsView() }
            .environment(WorkoutStore(context: container.mainContext))
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
