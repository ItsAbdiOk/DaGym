import GymCore
import SwiftData
import SwiftUI

extension WorkoutDetail {
    /// One run of consecutive exercises from the same routine, in `exercises`' original order.
    struct ExerciseGroup: Identifiable {
        var id: UUID
        var routineID: UUID?
        var glyph: RoutineGlyphInfo?
        var exercises: [WorkoutExerciseEntry]
    }

    /// `exercises` split into runs by `WorkoutExerciseEntry.routineID`, each carrying that
    /// routine's glyph. A workout built from one routine (or none — freestyle) always collapses
    /// to a single ungrouped run with no glyph, so it renders exactly as before multi-routine
    /// sessions existed — no empty header for the common case. Only a workout that actually
    /// combined more than one routine (`WorkoutStore.appendRoutine`) gets headers.
    var exerciseGroups: [ExerciseGroup] {
        let distinctRoutineIDs = Set(exercises.compactMap(\.routineID))
        guard distinctRoutineIDs.count > 1 else {
            return [ExerciseGroup(id: id, routineID: nil, glyph: nil, exercises: exercises)]
        }
        var groups: [ExerciseGroup] = []
        for entry in exercises {
            if let last = groups.last, last.routineID == entry.routineID {
                groups[groups.count - 1].exercises.append(entry)
            } else {
                let glyph = entry.routineID.map { routineGlyphs[$0] ?? .deletedRoutine }
                groups.append(
                    ExerciseGroup(
                        id: entry.routineID ?? entry.id, routineID: entry.routineID, glyph: glyph,
                        exercises: [entry]
                    )
                )
            }
        }
        return groups
    }
}

/// Read-only detail for one finished workout: title, time range, stats and
/// a card per exercise with its logged sets.
struct WorkoutDetailView: View {
    var workoutID: UUID

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
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
                        ForEach(detail.exerciseGroups) { group in
                            if let glyph = group.glyph {
                                groupHeader(glyph)
                            }
                            ForEach(group.exercises) { entry in ExerciseEntryCard(entry: entry) }
                        }
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
                Image(systemName: "chevron.left").accessibilityHidden(true)
                    .font(.system(size: 13, weight: .semibold))
                Text("History").dgLabel()
            }
            .foregroundStyle(DGColor.ink3)
        }
        .buttonStyle(.dgControl)
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
        DGAdaptiveStack(spacing: DGSpace.s3, threshold: .accessibility3) {
            StatTile(value: "\(detail.durationMinutes)", label: "Minutes").dgCard(radius: 14)
            StatTile(value: volumeText(detail), label: "Volume").dgCard(radius: 14)
            StatTile(value: "\(detail.setsDone)", label: "Sets").dgCard(radius: 14)
            StatTile(value: "\(detail.prCount)", label: "PRs", tint: DGColor.prGoldText).dgCard(radius: 14)
        }
    }

    /// Tonnage, with "· 5.0 km" beside it once the workout had a run in it.
    private func volumeText(_ detail: WorkoutDetail) -> String {
        let volume = preferences.formatWeight(kg: detail.volumeKg)
        guard detail.distanceMeters > 0 else { return volume }
        return "\(volume) · \(preferences.formatDistance(meters: detail.distanceMeters, decimals: 1))"
    }

    private func groupHeader(_ glyph: RoutineGlyphInfo) -> some View {
        HStack(spacing: DGSpace.s2) {
            RoutineGlyph(symbolName: glyph.symbolName, tint: glyph.tint, size: 28)
            Text(glyph.name)
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink2)
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func dateRangeLine(_ detail: WorkoutDetail) -> String {
        let dayText = dayFormatter.string(from: detail.startedAt).uppercased()
        let start = timeFormatter.string(from: detail.startedAt)
        guard let endedAt = detail.endedAt else { return "\(dayText) · \(start)" }
        return "\(dayText) · \(start)–\(timeFormatter.string(from: endedAt))"
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
                Text(HistoryView.pluralized(entry.sets.count, "set")).dgLabel()
            }
            VStack(spacing: DGSpace.s2) {
                ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                    ReadOnlySetRow(set: set, index: index + 1, isCardio: entry.isCardio)
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
    var isCardio = false

    @Environment(Preferences.self) private var preferences

    /// "5.00 km · 25:30 · 5:06 /km" for a run, "80 × 8" for a lift.
    private var line: String {
        isCardio ? set.cardioSummary(unit: preferences.distanceUnit)
            : "\(preferences.formatWeight(kg: set.weightKg)) × \(set.reps)"
    }

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            SetKindBadge(kind: set.kind, index: index)
            Text(line)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            // `effortTrackingEnabled` promises the effort column is hidden *everywhere*; this
            // read-only history row was one of the two places still showing it.
            if preferences.effortTrackingEnabled, let effort = set.effort {
                Text(effort.displayValue(scale: preferences.effortScale))
                    .font(DGFont.footnote)
                    .foregroundStyle(effort.color)
                    .padding(.horizontal, DGSpace.s2)
                    .frame(minHeight: 24)
                    .background(effort.color.opacity(0.16), in: Capsule())
                    .accessibilityLabel("Effort \(effort.displayValue(scale: preferences.effortScale))")
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            WorkoutDetailView(workoutID: UUID())
        }
            .environment(store)
            .environment(Preferences())
    }
}
