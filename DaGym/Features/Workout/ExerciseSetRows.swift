import GymCore
import SwiftUI

/// The set rows of one exercise — weight × reps `SetRow`s, one `TimedSetRow` per hold, or one
/// `CardioSetRow` per run — under their sighted-only column header. Shared by the on-deck card
/// (Cards / Compact layouts) and the List layout so logging behaves identically in each: same
/// bindings, keypad, steppers, swipe actions and done button, whichever chrome sits around them.
struct ExerciseSetRows: View {
    var entry: WorkoutExerciseEntry
    var effortScale: Effort.Scale
    /// Whether the next open set gets the coral "current" stroke. On in the on-deck card; the
    /// List layout shows every exercise's rows and only marks the on-deck one.
    var highlightsCurrent = true
    var onTapWeight: (UUID) -> Void
    var onTapReps: (UUID) -> Void
    var onTapEffort: (UUID) -> Void
    var onToggleDone: (SetEntry) -> Void
    var onStartTimed: (UUID) -> Void
    var onTapCardioField: (UUID, ActiveSheet.KeypadField) -> Void
    var onDeleteSet: (UUID) -> Void
    var onChangeSetKind: (UUID, SetKind) -> Void
    var onInsertSet: (UUID, SetKind) -> Void
    var onAdjustWeight: (UUID, Double) -> Void
    var onAdjustReps: (UUID, Int) -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// "Add incline" on a cardio exercise whose kit has no incline dial.
    @State private var inclineRevealed = false

    var body: some View {
        switch entry.onDeckRows {
        case .loaded:
            columnHeader
            setRows
        case .timed(let startSetID):
            timedColumnHeader
            timedRows(startSetID: startSetID).padding(.top, DGSpace.s2)
        case .cardio(let startSetID):
            cardioColumnHeader
            cardioRows(startSetID: startSetID).padding(.top, DGSpace.s2)
        }
    }

    // MARK: Column headers

    /// Column headers are sighted-only: every control in the rows below carries its own
    /// VoiceOver label ("Weight", "Reps", …), so reading "SET PREV KG" first is noise. The
    /// "Prev" column disappears with the row's ghost at accessibility sizes.
    private var columnHeader: some View {
        let showsPrevious = !preferences.showSetSteppers && !dynamicTypeSize.isAccessibilitySize
        return HStack(spacing: 0) {
            Text("Set").frame(width: SetRow.Column.index)
            if showsPrevious {
                Text("Previous").padding(.leading, DGSpace.s1).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            Text(preferences.unitSymbol).frame(minWidth: SetRow.Column.weight)
            Text("Reps").frame(minWidth: SetRow.Column.reps)
            if preferences.effortTrackingEnabled {
                Text(effortScale == .rpe ? "RPE" : "RIR").frame(width: SetRow.Column.effort)
            }
            Color.clear.frame(width: SetRow.Column.done, height: 1)
        }
        .padding(.horizontal, DGSpace.s1)
        .padding(.bottom, DGSpace.s2)
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

    // MARK: Rows

    private func cardioRows(startSetID: UUID?) -> some View {
        let badges = entry.workingBadgeIndices
        return VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                CardioSetRow(
                    setEntry: set, badgeIndex: badges[index], rowIndex: index,
                    isCurrent: highlightsCurrent && set.id == startSetID, showsIncline: showsIncline,
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
                    set: set, badgeIndex: badges[index], isCurrent: highlightsCurrent && set.id == startSetID,
                    onStart: { onStartTimed(set.id) }, onToggleDone: { onToggleDone(set) }
                )
            }
        }
    }

    private var setRows: some View {
        let firstOpenID = entry.nextOpenSetID
        let badges = entry.workingBadgeIndices
        return VStack(spacing: 6) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    set: set, badgeIndex: badges[index], rowIndex: index,
                    isCurrent: highlightsCurrent && set.id == firstOpenID,
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
