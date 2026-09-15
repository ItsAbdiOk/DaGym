import GymCore
import SwiftUI

/// The detailed, fully expanded card for the exercise currently being worked.
struct OnDeckExerciseCard: View {
    var entry: WorkoutExerciseEntry
    var effortScale: Effort.Scale
    var inventory: ProgressionEquipment?
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
                PlateChip(weightKg: plateSet.weightKg, bar: bar, inventory: inventory) {
                    onTapWeight(plateSet.id)
                }
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
        let badges = entry.workingBadgeIndices
        return VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                CardioSetRow(
                    setEntry: set, badgeIndex: badges[index], rowIndex: index,
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
        let badges = entry.workingBadgeIndices
        return VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                TimedSetRow(
                    set: set, badgeIndex: badges[index], isCurrent: set.id == startSetID,
                    onStart: { onStartTimed(set.id) }, onToggleDone: { onToggleDone(set) }
                )
            }
        }
    }

    private var setRows: some View {
        let firstOpenID = entry.nextOpenSetID
        let badges = entry.workingBadgeIndices
        return VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    set: set, badgeIndex: badges[index], rowIndex: index,
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
}

extension WorkoutExerciseEntry {
    /// The working-set number each row's badge shows ("1, 2, 3" over the working sets; a
    /// warm-up before the first shows 0), in one pass — a per-row prefix count was O(n²) per
    /// card render, and this renders on every set edit.
    var workingBadgeIndices: [Int] {
        var count = 0
        return sets.map { set in
            if set.kind == .working { count += 1 }
            return count
        }
    }
}
