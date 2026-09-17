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

/// Detail for one finished workout: the title in the bar, time range, four stat tiles and a
/// white row group per exercise with its logged sets — read-only except the session note,
/// which opens `NotesSheet` on tap.
struct WorkoutDetailView: View {
    var workoutID: UUID

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var detail: WorkoutDetail?
    @State private var isEditingNote = false

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                if let detail {
                    VStack(alignment: .leading, spacing: DGSpace.s3) {
                        titleBlock(detail)
                        statRow(detail)
                        ForEach(detail.exerciseGroups) { group in
                            if let glyph = group.glyph {
                                groupHeader(glyph)
                            }
                            ForEach(group.exercises) { entry in ExerciseEntryCard(entry: entry) }
                        }
                        if !detail.notes.isEmpty || detail.canEditNotes { notesCard(detail) }
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, 110)
                }
            }
        }
        .navigationTitle(detail?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        // A note saved here bumps `changeToken`; so does a delete or an import elsewhere.
        .refreshOnStoreChange(refresh)
        .sheet(isPresented: $isEditingNote) {
            NotesSheet(title: "Session note", text: detail?.notes ?? "") { text in
                store.updateWorkoutNote(id: workoutID, text: text)
                refresh()
            }
        }
    }

    private func titleBlock(_ detail: WorkoutDetail) -> some View {
        HStack(spacing: DGSpace.s2) {
            Text(Self.dateRangeLine(detail))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            if detail.isBackfilled {
                DGTag(text: "Backfilled", tint: DGColor.infoText, wash: DGColor.info.opacity(0.16))
            }
        }
        .padding(.horizontal, DGSpace.s1)
    }

    private func statRow(_ detail: WorkoutDetail) -> some View {
        DGAdaptiveGrid(columns: 4, spacing: DGSpace.s2) {
            ProgressStatTile(value: "\(detail.durationMinutes)", label: "Minutes")
            ProgressStatTile(value: volumeText(detail), label: preferences.unitSymbol)
            ProgressStatTile(value: "\(detail.setsDone)", label: "Sets")
            ProgressStatTile(value: "\(detail.prCount)", label: detail.prCount == 1 ? "PR" : "PRs")
        }
    }

    /// Tonnage, with "· 5.0 km" beside it once the workout had a run in it.
    private func volumeText(_ detail: WorkoutDetail) -> String {
        let volume = preferences.formatVolume(kg: detail.volumeKg)
        guard detail.distanceMeters > 0 else { return volume }
        return "\(volume) · \(preferences.formatDistance(meters: detail.distanceMeters, decimals: 1))"
    }

    private func groupHeader(_ glyph: RoutineGlyphInfo) -> some View {
        HStack(spacing: DGSpace.s2) {
            RoutineGlyph(symbolName: glyph.symbolName, tint: glyph.tint, size: 28)
            Text(glyph.name)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink2)
        }
        .padding(.top, DGSpace.s2)
        .padding(.horizontal, DGSpace.s1)
    }

    private func refresh() {
        detail = store.workoutDetail(id: workoutID)
    }

    /// The session note. Tappable — opening `NotesSheet` — on any finished main-store workout,
    /// backfilled or synced from the Watch alike; a read-only card for an imported Apple Health
    /// session. With no note yet the card is the "Add a note" affordance.
    @ViewBuilder
    private func notesCard(_ detail: WorkoutDetail) -> some View {
        if detail.canEditNotes {
            Button { isEditingNote = true } label: {
                notesCardContent(detail)
            }
            .buttonStyle(.dgCard)
            .dgCard(radius: 20, padding: DGSpace.s4)
            .accessibilityLabel(detail.notes.isEmpty ? "Add a note" : "Notes, \(detail.notes)")
            .accessibilityHint("Edits the session note")
            .accessibilityIdentifier(A11yID.historyNote)
        } else {
            notesCardContent(detail).dgCard(radius: 20, padding: DGSpace.s4)
        }
    }

    private func notesCardContent(_ detail: WorkoutDetail) -> some View {
        HStack(alignment: .top, spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                ProgressCardTitle(title: "Notes")
                if detail.notes.isEmpty {
                    Text("Add a note")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink3)
                } else {
                    // The whole note, however long: a card that clipped it would hide exactly
                    // what the lifter opened the workout to read.
                    Text(detail.notes)
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if detail.canEditNotes {
                Image(systemName: detail.notes.isEmpty ? "plus" : "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let dayText = dayFormatter.string(from: detail.startedAt)
        let start = timeFormatter.string(from: detail.startedAt)
        guard let endedAt = detail.endedAt else { return "\(dayText) · \(start)" }
        return "\(dayText) · \(start)–\(timeFormatter.string(from: endedAt))"
    }
}

/// One exercise's read-only set list: the exercise name as the group's first row, then one
/// hairlined row per set.
private struct ExerciseEntryCard: View {
    var entry: WorkoutExerciseEntry

    var body: some View {
        TrainRowGroup {
            HStack {
                Text(entry.exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Text(HistoryView.pluralized(entry.sets.count, "set"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(DGColor.ink3)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .trainRowDivider(isLast: entry.sets.isEmpty)
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                ReadOnlySetRow(
                    set: set, index: index + 1, isCardio: entry.isCardio,
                    isLast: index == entry.sets.count - 1
                )
            }
        }
    }
}

/// One read-only "badge · weight × reps · effort" row.
private struct ReadOnlySetRow: View {
    var set: SetEntry
    var index: Int
    var isCardio = false
    var isLast = false

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
                .font(.system(size: 15))
                .monospacedDigit()
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
        .padding(.horizontal, 15)
        .frame(minHeight: 46)
        .trainRowDivider(isLast: isLast)
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
