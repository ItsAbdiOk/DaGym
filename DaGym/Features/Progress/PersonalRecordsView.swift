import SwiftData
import SwiftUI

/// Every cached personal record, grouped by exercise. Gold accents throughout — the one
/// screen where that colour is earned.
struct PersonalRecordsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var groups: [ExerciseRecords] = []

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    if groups.isEmpty {
                        EmptyState(
                            symbol: "star",
                            title: "No Records Yet",
                            message: "Finish a workout and your best lifts will show up here."
                        )
                    } else {
                        VStack(spacing: DGSpace.s4) {
                            ForEach(groups) { group in
                                ExerciseRecordsCard(group: group)
                            }
                        }
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { groups = store.personalRecords(unit: preferences.weightUnit) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Records")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.prGoldText)
            Text("Your best lift of every kind, per exercise.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }
}

/// One exercise's records, gold star per line.
private struct ExerciseRecordsCard: View {
    var group: ExerciseRecords

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text(group.exerciseName)
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            VStack(spacing: DGSpace.s2) {
                ForEach(group.records) { record in
                    RecordRow(record: record)
                }
            }
        }
        .dgCard(fill: DGColor.prGold.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.prGold.opacity(0.3), lineWidth: 1)
        }
    }
}

/// A single record line: gold star, kind label, formatted value and date.
private struct RecordRow: View {
    var record: PersonalRecordLine

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DGColor.prGold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.kindLabel).dgLabel(DGColor.prGoldText)
                Text(record.line)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer()
            Text(Self.dateLabel(record.date))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
        .accessibilityElement(children: .combine)
        .frame(minHeight: DGTap.min)
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        PersonalRecordsView()
            .environment(WorkoutStore(context: container.mainContext))
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
