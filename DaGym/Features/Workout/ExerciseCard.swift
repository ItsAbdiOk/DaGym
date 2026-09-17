import GymCore
import SwiftUI

/// One exercise in the active workout list. In the Cards and Compact layouts it renders one of
/// three states: on-deck (full card with sets — `OnDeckExerciseCard`), collapsed incomplete
/// row, or a completed one-liner (both in `ExerciseCardRows.swift`). The List layout shows
/// every exercise as a header row over all of its set rows (`ListExerciseSection`). See
/// mockups 02_00 / 02_01 and design sheet 01_04.
struct ExerciseCard: View {
    var entry: WorkoutExerciseEntry
    var isOnDeck: Bool
    var effortScale: Effort.Scale
    var layout: WorkoutLayout = .cards
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
    /// The active equipment profile for the on-deck plate chip (see `PlateChip.inventory`).
    var inventory: ProgressionEquipment?

    var body: some View {
        if layout == .list {
            ListExerciseSection(
                entry: entry, isOnDeck: isOnDeck, rows: rows(highlightsCurrent: isOnDeck),
                onMore: onMore, onNote: onNote
            )
        } else if entry.isComplete {
            CompletedExerciseRow(entry: entry)
        } else if isOnDeck {
            OnDeckExerciseCard(
                entry: entry, layout: layout, inventory: inventory, rows: rows(highlightsCurrent: true),
                onTapWeight: onTapWeight, onMore: onMore, onNote: onNote
            )
        } else {
            CollapsedExerciseRow(entry: entry, onStartTimed: onStartTimed)
        }
    }

    /// The one set-row stack every layout logs through.
    private func rows(highlightsCurrent: Bool) -> ExerciseSetRows {
        ExerciseSetRows(
            entry: entry, effortScale: effortScale, highlightsCurrent: highlightsCurrent,
            onTapWeight: onTapWeight, onTapReps: onTapReps, onTapEffort: onTapEffort,
            onToggleDone: onToggleDone, onStartTimed: onStartTimed, onTapCardioField: onTapCardioField,
            onDeleteSet: onDeleteSet, onChangeSetKind: onChangeSetKind, onInsertSet: onInsertSet,
            onAdjustWeight: onAdjustWeight, onAdjustReps: onAdjustReps
        )
    }
}

/// The List layout's block for one exercise: a dense header row (name, done count, notes and
/// more buttons) over every set row, with a hairline instead of card chrome — so a superset's
/// members read as one continuous list.
struct ListExerciseSection: View {
    var entry: WorkoutExerciseEntry
    var isOnDeck: Bool
    var rows: ExerciseSetRows
    var onMore: () -> Void
    var onNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rows.padding(.top, DGSpace.s2)
        }
        .padding(.bottom, DGSpace.s3)
        .overlay(alignment: .bottom) { Divider().overlay(DGColor.hairline) }
    }

    private var header: some View {
        HStack(spacing: DGSpace.s2) {
            Text(entry.exercise.name)
                .font(DGFont.title3)
                .foregroundStyle(isOnDeck ? DGColor.coralText : DGColor.ink1)
                .lineLimit(2)
            if isOnDeck {
                Text("On deck").dgLabel(DGColor.coralText)
            }
            Spacer(minLength: DGSpace.s2)
            Text("\(entry.doneCount)/\(entry.sets.count)")
                .dgMetric(DGFont.subhead)
                .foregroundStyle(entry.isComplete ? DGColor.success : DGColor.ink3)
                .accessibilityLabel("\(entry.doneCount) of \(entry.sets.count) sets done")
            DGIconButton(
                symbol: "text.bubble", size: 36, tint: DGColor.ink2, accessibilityLabel: "Notes",
                action: onNote
            )
            DGIconButton(symbol: "ellipsis", size: 36, accessibilityLabel: "More options", action: onMore)
        }
        .frame(minHeight: DGTap.min)
        .dgDenseType()
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
