import GymCore
import SwiftUI

/// One exercise in the active workout list. Renders one of three layouts:
/// on-deck (full card with sets), collapsed incomplete row, or a completed
/// one-liner. See mockups 02_00 / 02_01 and design sheet 01_04.
struct ExerciseCard: View {
    var entry: WorkoutExerciseEntry
    var isOnDeck: Bool
    var effortScale: Effort.Scale
    var onTapWeight: (UUID) -> Void
    var onTapReps: (UUID) -> Void
    var onTapEffort: (UUID) -> Void
    var onToggleDone: (SetEntry) -> Void
    var onMore: () -> Void
    var onStartTimed: (UUID) -> Void
    /// A cardio row's time / distance / incline tap: opens the keypad on that field.
    var onTapCardioField: (UUID, ActiveSheet.KeypadField) -> Void = { _, _ in }
    /// Note button in the on-deck header, and the set-row swipe actions.
    var onNote: () -> Void = {}
    var onDeleteSet: (UUID) -> Void = { _ in }
    var onChangeSetKind: (UUID, SetKind) -> Void = { _, _ in }
    /// Drop-set / rest-pause swipe shortcuts and the optional ± steppers.
    var onInsertSet: (UUID, SetKind) -> Void = { _, _ in }
    var onAdjustWeight: (UUID, Double) -> Void = { _, _ in }
    var onAdjustReps: (UUID, Int) -> Void = { _, _ in }

    var body: some View {
        if entry.isComplete {
            CompletedExerciseRow(entry: entry)
        } else if isOnDeck {
            OnDeckExerciseCard(
                entry: entry, effortScale: effortScale,
                onTapWeight: onTapWeight, onTapReps: onTapReps, onTapEffort: onTapEffort,
                onToggleDone: onToggleDone, onMore: onMore, onStartTimed: onStartTimed,
                onTapCardioField: onTapCardioField, onNote: onNote, onDeleteSet: onDeleteSet,
                onChangeSetKind: onChangeSetKind, onInsertSet: onInsertSet,
                onAdjustWeight: onAdjustWeight, onAdjustReps: onAdjustReps
            )
        } else {
            CollapsedExerciseRow(entry: entry, onStartTimed: onStartTimed)
        }
    }
}

/// Which rows the on-deck card lays out: weight × reps `SetRow`s, one `TimedSetRow` per hold
/// with Start on the next open one, or one `CardioSetRow` per run. Pure so it can be asserted
/// without rendering the card.
enum OnDeckRows: Equatable {
    case loaded
    case timed(startSetID: UUID?)
    case cardio(startSetID: UUID?)
}

extension WorkoutExerciseEntry {
    var nextOpenSetID: UUID? { sets.first { !$0.isDone }?.id }

    var onDeckRows: OnDeckRows {
        if isCardio { return .cardio(startSetID: nextOpenSetID) }
        return isTimed ? .timed(startSetID: nextOpenSetID) : .loaded
    }

    /// The incline column shows for treadmill/stair kit, or once any row carries an incline.
    var showsInclineByDefault: Bool {
        exercise.hasInclineByDefault || sets.contains { $0.inclinePercent != nil }
    }
}

/// The detailed, fully expanded card for the exercise currently being worked.
private struct OnDeckExerciseCard: View {
    var entry: WorkoutExerciseEntry
    var effortScale: Effort.Scale
    var onTapWeight: (UUID) -> Void
    var onTapReps: (UUID) -> Void
    var onTapEffort: (UUID) -> Void
    var onToggleDone: (SetEntry) -> Void
    var onMore: () -> Void
    var onStartTimed: (UUID) -> Void
    var onTapCardioField: (UUID, ActiveSheet.KeypadField) -> Void
    var onNote: () -> Void
    var onDeleteSet: (UUID) -> Void
    var onChangeSetKind: (UUID, SetKind) -> Void
    var onInsertSet: (UUID, SetKind) -> Void
    var onAdjustWeight: (UUID, Double) -> Void
    var onAdjustReps: (UUID, Int) -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// "Add incline" on a cardio card whose kit has no incline dial.
    @State private var inclineRevealed = false

    /// `Preferences.compactWorkoutLayout`: just the header and the rows — no on-deck pill,
    /// last-3 strip, why-card or plate chip.
    private var isCompact: Bool { preferences.compactWorkoutLayout }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isCompact {
                Text("On deck").dgLabel(DGColor.coralText)
                    .padding(.horizontal, DGSpace.s2)
                    .padding(.vertical, 4)
                    .background(DGColor.coralWash, in: Capsule())
                    .padding(.bottom, DGSpace.s2)
            }
            header
            if let plateSet, let bar = entry.exercise.bar, !isCompact {
                PlateChip(weightKg: plateSet.weightKg, bar: bar) { onTapWeight(plateSet.id) }
                    .padding(.top, DGSpace.s3)
            }
            if !entry.lastSessions.isEmpty, !isCompact {
                lastSessionsStrip.padding(.top, DGSpace.s4)
            }
            if let whyTitle = entry.whyTitle, let whyBody = entry.whyBody, !isCompact {
                WhyCard(title: whyTitle, message: whyBody, labelColor: whyLabelColor)
                    .padding(.top, DGSpace.s3)
            }
            switch entry.onDeckRows {
            case .loaded:
                columnHeader.padding(.top, DGSpace.s4)
                setRows.padding(.top, DGSpace.s2)
            case .timed(let startSetID):
                timedColumnHeader.padding(.top, DGSpace.s4)
                timedRows(startSetID: startSetID).padding(.top, DGSpace.s2)
            case .cardio(let startSetID):
                cardioColumnHeader.padding(.top, DGSpace.s4)
                cardioRows(startSetID: startSetID).padding(.top, DGSpace.s2)
            }
        }
        .dgCard()
    }

    private var header: some View {
        HStack(spacing: DGSpace.s3) {
            ExerciseThumbnail(exercise: entry.exercise)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise.name)
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Text(footnote)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            Spacer(minLength: 0)
            DGIconButton(
                symbol: "text.bubble", size: 36, tint: DGColor.ink2, accessibilityLabel: "Notes",
                action: onNote
            )
            DGIconButton(symbol: "ellipsis", accessibilityLabel: "More options", action: onMore)
        }
    }

    /// The set the plate chip describes: the next open loaded set, once it has a weight. A hold
    /// or a run has no bar to load.
    private var plateSet: SetEntry? {
        guard !entry.isTimed, !entry.isCardio, let set = entry.sets.first(where: { !$0.isDone }),
              set.weightKg > 0 else { return nil }
        return set
    }

    private var whyLabelColor: Color {
        entry.whyKind == .deload ? DGColor.warning : DGColor.aiVioletText
    }

    private var footnote: String {
        let step = entry.doneCount + 1 <= entry.sets.count ? entry.doneCount + 1 : entry.sets.count
        let restSeconds = entry.exercise.restSeconds(defaultingTo: preferences.defaultRestSeconds)
        let rest = restSeconds > 0 ? WorkoutSession.clock(restSeconds) : "off"
        if entry.isCardio {
            // Last session's distance and time instead of a load increment a run doesn't have.
            let last = entry.lastSessions.first.map { "last \($0)" } ?? "first time"
            return "Set \(step) of \(entry.sets.count) · rest \(rest) · \(last)"
        }
        // The same snapped step the ± steppers and keypad actually move by.
        let stepKg = SetRow.weightStepKg(entry.exercise.incrementKg, unit: preferences.weightUnit)
        let incrementValue = preferences.formatWeight(kg: stepKg)
        let increment = "\(incrementValue) \(preferences.unitSymbol)"
        return "Set \(step) of \(entry.sets.count) · rest \(rest) · increment \(increment)"
    }

    private var lastSessionsStrip: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Last 3 sessions").dgLabel()
            HStack(spacing: DGSpace.s3) {
                Text(entry.lastSessions.joined(separator: " · "))
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink2)
                Spacer(minLength: DGSpace.s2)
                // The three numbers beside it say the same thing in words.
                Sparkline(values: entry.sparkline)
                    .frame(width: 60, height: 22)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Column headers are sighted-only: every control in the rows below carries its own
    /// VoiceOver label ("Weight", "Reps", …), so reading "SET PREV KG" first is noise. The
    /// "Prev" column disappears with the row's ghost at accessibility sizes.
    private var columnHeader: some View {
        HStack(spacing: DGSpace.s3) {
            Text("Set").frame(minWidth: 28, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                Text("Prev").frame(minWidth: 44, alignment: .leading)
            }
            Text(preferences.unitSymbol.uppercased()).frame(minWidth: 44, alignment: .leading)
            Text("Reps").frame(minWidth: 30, alignment: .leading)
            if preferences.effortTrackingEnabled {
                Text(effortScale == .rpe ? "Rpe" : "Rir").frame(minWidth: 28, alignment: .leading)
            }
        }
        .dgLabel()
        .dgDenseType()
        .accessibilityHidden(true)
    }

    private var timedColumnHeader: some View {
        HStack(spacing: DGSpace.s3) {
            Text("Set").frame(minWidth: 28, alignment: .leading)
            Text("Target").frame(minWidth: 44, alignment: .leading)
            Text("Held").frame(minWidth: 44, alignment: .leading)
        }
        .dgLabel()
        .dgDenseType()
        .accessibilityHidden(true)
    }

    private var showsIncline: Bool { inclineRevealed || entry.showsInclineByDefault }

    private var cardioColumnHeader: some View {
        HStack(spacing: DGSpace.s3) {
            Text("Set").frame(minWidth: 28, alignment: .leading)
            Text("").frame(width: 28).accessibilityHidden(true)
            Text("Time").frame(minWidth: 44, alignment: .leading)
            Text(preferences.distanceUnit.symbol.uppercased()).frame(minWidth: 44, alignment: .leading)
            if showsIncline {
                Text("Incl").frame(minWidth: 44, alignment: .leading)
            } else {
                Button("Add incline") { inclineRevealed = true }
                    .buttonStyle(.dgControl)
                    .foregroundStyle(DGColor.coralText)
            }
        }
        .dgLabel()
        .dgDenseType()
    }

    private func cardioRows(startSetID: UUID?) -> some View {
        VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                CardioSetRow(
                    setEntry: set, badgeIndex: workingIndex(upTo: index), rowIndex: index,
                    isCurrent: set.id == startSetID, showsIncline: showsIncline,
                    onStart: { onStartTimed(set.id) },
                    onTapTime: { onTapCardioField(set.id, .minutes) },
                    onTapDistance: { onTapCardioField(set.id, .distance) },
                    onTapIncline: { onTapCardioField(set.id, .incline) },
                    onToggleDone: { onToggleDone(set) },
                    onDelete: { onDeleteSet(set.id) },
                    onChangeKind: { kind in onChangeSetKind(set.id, kind) }
                )
            }
        }
    }

    private func timedRows(startSetID: UUID?) -> some View {
        VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                TimedSetRow(
                    set: set, badgeIndex: workingIndex(upTo: index), isCurrent: set.id == startSetID,
                    onStart: { onStartTimed(set.id) }, onToggleDone: { onToggleDone(set) }
                )
            }
        }
    }

    private var setRows: some View {
        let firstOpenID = entry.nextOpenSetID
        return VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    set: set, badgeIndex: workingIndex(upTo: index), rowIndex: index,
                    isCurrent: set.id == firstOpenID,
                    effortScale: effortScale, isPerSide: entry.exercise.isPerSide,
                    incrementKg: entry.exercise.incrementKg,
                    onTapWeight: { onTapWeight(set.id) }, onTapReps: { onTapReps(set.id) },
                    onTapEffort: { onTapEffort(set.id) }, onToggleDone: { onToggleDone(set) },
                    onDelete: { onDeleteSet(set.id) },
                    onChangeKind: { kind in onChangeSetKind(set.id, kind) },
                    onInsertBelow: { kind in onInsertSet(set.id, kind) },
                    onAdjustWeight: { delta in onAdjustWeight(set.id, delta) },
                    onAdjustReps: { delta in onAdjustReps(set.id, delta) }
                )
            }
        }
    }

    private func workingIndex(upTo index: Int) -> Int {
        entry.sets.prefix(index + 1).filter { $0.kind == .working }.count
    }
}

/// Collapsed one-line row for an incomplete exercise that isn't on deck yet.
private struct CollapsedExerciseRow: View {
    var entry: WorkoutExerciseEntry
    var onStartTimed: (UUID) -> Void

    @Environment(Preferences.self) private var preferences

    private var firstOpenSetID: UUID? { entry.nextOpenSetID ?? entry.sets.first?.id }

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            ExerciseThumbnail(exercise: entry.exercise, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise.name)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Text(summaryLine)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            Spacer(minLength: DGSpace.s2)
            if entry.isTimed {
                Button {
                    if let setID = firstOpenSetID { onStartTimed(setID) }
                } label: {
                    Text("Start")
                        .font(DGFont.condensedLabel(12))
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                        .padding(.horizontal, DGSpace.s3)
                        .frame(minHeight: 36)
                        .dgGlass(.regular, in: Capsule())
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel("Start \(entry.exercise.name)")
            } else {
                Text("\(entry.doneCount)/\(entry.sets.count)")
                    .dgMetric(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
                    .accessibilityLabel("\(entry.doneCount) of \(entry.sets.count) sets done")
            }
        }
        .dgCard(padding: DGSpace.s4)
        // One row, one element — the "Start" button (timed holds) stays reachable as a child.
        .accessibilityElement(children: entry.isTimed ? .contain : .combine)
    }

    private var summaryLine: String {
        guard let first = entry.sets.first else { return entry.exercise.equipment }
        if entry.isCardio {
            return "\(entry.sets.count) × \(first.cardioSummary(unit: preferences.distanceUnit))"
        }
        if entry.isTimed {
            let target = first.targetSeconds ?? 0
            return "\(entry.sets.count) holds · target \(WorkoutSession.clock(target))"
        }
        // A weight of 0 means "not entered yet" (or bodyweight) — nothing worth printing.
        guard first.weightKg > 0 else { return "\(entry.sets.count) × \(first.reps)" }
        let weight = preferences.formatWeight(kg: first.weightKg)
        let suffix = entry.exercise.isPerSide ? "\(preferences.unitSymbol) per side" : preferences.unitSymbol
        return "\(entry.sets.count) × \(first.reps) · \(weight) \(suffix)"
    }
}

/// One-liner for a finished exercise.
private struct CompletedExerciseRow: View {
    var entry: WorkoutExerciseEntry

    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Completed").dgLabel(DGColor.success)
            Text(summary)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(padding: DGSpace.s4)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let name = entry.exercise.name.uppercased()
        guard let first = entry.sets.first else { return name }
        if entry.isCardio {
            let meters = entry.distanceMeters
            let seconds = entry.sets.compactMap(\.durationSeconds).reduce(0, +)
            let line = SetEntry(weightKg: 0, reps: 0, durationSeconds: seconds, distanceMeters: meters)
                .cardioSummary(unit: preferences.distanceUnit)
            return "\(name) · \(line)"
        }
        if entry.isTimed {
            let best = entry.sets.compactMap(\.durationSeconds).max() ?? 0
            return "\(name) · \(entry.sets.count) holds · best \(WorkoutSession.clock(best))"
        }
        guard first.weightKg > 0 else { return "\(name) · \(entry.sets.count) × \(first.reps)" }
        let weight = preferences.formatWeight(kg: first.weightKg)
        return "\(name) · \(entry.sets.count) × \(first.reps) · \(weight) \(preferences.unitSymbol)"
    }
}

private struct ExerciseThumbnail: View {
    var exercise: ExerciseInfo
    var size: CGFloat = 44

    var body: some View {
        BodyMapView(
            side: BodyMapMuscleMapping.thumbnailSide(forPrimary: exercise.primary),
            mode: .hit,
            intensity: exercise.hitMap
        )
            .padding(6)
            .frame(width: size, height: size)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
            // Decorative: the exercise name beside it is the content.
            .accessibilityHidden(true)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: DGSpace.s4) {
            ForEach(SampleData.makeSession().exercises) { entry in
                ExerciseCard(
                    entry: entry, isOnDeck: entry.exercise.id == SampleData.bench.id, effortScale: .rpe,
                    onTapWeight: { _ in }, onTapReps: { _ in }, onTapEffort: { _ in },
                    onToggleDone: { _ in }, onMore: {}, onStartTimed: { _ in }
                )
            }
        }
        .padding()
    }
    .background(AmbientWash())
    .environment(Preferences())
}
