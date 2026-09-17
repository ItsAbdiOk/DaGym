import GymCore
import SwiftUI

/// The detailed, fully expanded card for the exercise currently being worked (prototype
/// `sWorkout`, the deck card): art, name and muscles with the "…" button; "Set 1 of 4 · rest
/// 2:30 · increment 2.5 kg"; the plate chip and the tinted progression chip with its
/// one-sentence reason; the "LAST 3" strip with its sparkline; the set table; "Add set" and
/// "Swap". `rows` is the same `ExerciseSetRows` the List layout renders, so logging is
/// identical in every layout.
struct OnDeckExerciseCard: View {
    var entry: WorkoutExerciseEntry
    var layout: WorkoutLayout
    var inventory: ProgressionEquipment?
    var rows: ExerciseSetRows
    var onTapWeight: (UUID) -> Void
    var onMore: () -> Void
    var onAddSet: () -> Void
    var onSwap: () -> Void
    /// The name and the "Last 3" strip open the exercise's detail (history, chart, notes).
    var onOpenExercise: () -> Void = {}

    @Environment(Preferences.self) private var preferences

    /// `WorkoutLayout.compact`: just the header and the rows — no chips, last-3 strip or
    /// reason line.
    private var showsExtras: Bool { layout.showsCardExtras }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(setLine)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DGColor.ink3)
                .padding(.top, DGSpace.s3)
            if showsExtras {
                chips.padding(.top, 10)
                if let whyBody = entry.whyBody {
                    Text(whyBody)
                        .font(.system(size: 12))
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DGSpace.s2)
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12).italic())
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DGSpace.s2)
                        .accessibilityLabel("Note: \(note)")
                }
                if !entry.lastSessions.isEmpty {
                    lastSessionsStrip.padding(.top, 14)
                }
            }
            rows.padding(.top, 14)
            DGAdaptiveStack(spacing: DGSpace.s2) {
                WorkoutPillButton(title: "Add set", style: .ink, radius: DGRadius.sm, action: onAddSet)
                WorkoutPillButton(title: "Swap", style: .ink, radius: DGRadius.sm, action: onSwap)
            }
            .padding(.top, DGSpace.s3)
        }
        .dgCard(radius: DGRadius.lg, padding: DGSpace.s4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DGSpace.s3) {
            Button(action: onOpenExercise) {
                HStack(alignment: .top, spacing: DGSpace.s3) {
                    ExerciseThumbnail(exercise: entry.exercise, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(entry.exercise.name)
                                .font(.system(size: 16.5, weight: .semibold))
                                .foregroundStyle(DGColor.ink1)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DGColor.ink4)
                        }
                        Text(entry.exercise.muscleLine)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DGColor.ink3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.dgRow)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the exercise")
            Spacer(minLength: 0)
            WorkoutRoundButton(
                symbol: "ellipsis", size: 30, accessibilityLabel: "More options", action: onMore
            )
        }
    }

    /// Plate maths on one line, the progression chip on the next — the prototype wraps them.
    @ViewBuilder
    private var chips: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let plateSet, let bar = entry.exercise.bar {
                PlateChip(weightKg: plateSet.weightKg, bar: bar, inventory: inventory) {
                    onTapWeight(plateSet.id)
                }
            }
            if let whyTitle = entry.whyTitle {
                Text(whyTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(whyTint)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 24)
                    .background(
                        whyTint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: DGRadius.chip, style: .continuous)
                    )
                    .accessibilityLabel("Why: \(whyTitle)")
            }
        }
    }

    /// The set the plate chip describes: the next open loaded set, once it has a weight. A hold
    /// or a run has no bar to load.
    private var plateSet: SetEntry? {
        guard !entry.isTimed, !entry.isCardio, let set = entry.sets.first(where: { !$0.isDone }),
              set.weightKg > 0 else { return nil }
        return set
    }

    /// Accent for a coach prescription; the warning amber for a deload back-off, so it reads
    /// as a heads-up rather than routine coaching.
    private var whyTint: Color {
        entry.whyKind == .deload ? DGColor.warning : DGColor.coralText
    }

    private var setLine: String {
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

    /// "LAST 3 · 80×8 · 80×8 · 82.5×7 ▁▂▃ ›" — a door to the exercise's full history.
    private var lastSessionsStrip: some View {
        Button(action: onOpenExercise) {
            HStack(spacing: DGSpace.s2) {
                Text("Last 3").dgLabel()
                Text(entry.lastSessions.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: DGSpace.s2)
                // The three numbers beside it say the same thing in words.
                Sparkline(values: entry.sparkline)
                    .frame(width: 46, height: 16)
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                DGColor.ink1.opacity(0.045),
                in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
            )
        }
        .buttonStyle(.dgCard)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the exercise's history")
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
