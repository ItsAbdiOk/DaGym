import GymCore
import SwiftUI

/// One exercise in the active workout list. Renders one of three layouts:
/// on-deck (full card with sets — `OnDeckExerciseCard`), collapsed incomplete row, or a
/// completed one-liner (both in `ExerciseCardRows.swift`). See mockups 02_00 / 02_01 and
/// design sheet 01_04.
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
    /// The active equipment profile for the on-deck plate chip (see `PlateChip.inventory`).
    var inventory: ProgressionEquipment?

    var body: some View {
        if entry.isComplete {
            CompletedExerciseRow(entry: entry)
        } else if isOnDeck {
            OnDeckExerciseCard(
                entry: entry, effortScale: effortScale, inventory: inventory,
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
