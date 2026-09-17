import GymCore
import SwiftUI

/// The detailed, fully expanded card for the exercise currently being worked. `rows` is the
/// same `ExerciseSetRows` the List layout renders, so logging is identical in every layout.
struct OnDeckExerciseCard: View {
    var entry: WorkoutExerciseEntry
    var layout: WorkoutLayout
    var inventory: ProgressionEquipment?
    var rows: ExerciseSetRows
    var onTapWeight: (UUID) -> Void
    var onMore: () -> Void
    var onNote: () -> Void

    @Environment(Preferences.self) private var preferences

    /// `WorkoutLayout.compact`: just the header and the rows — no on-deck pill, last-3 strip,
    /// why-card or plate chip.
    private var showsExtras: Bool { layout.showsCardExtras }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsExtras {
                Text("On deck").dgLabel(DGColor.coralText)
                    .padding(.horizontal, DGSpace.s2)
                    .padding(.vertical, 4)
                    .background(DGColor.coralWash, in: Capsule())
                    .padding(.bottom, DGSpace.s2)
            }
            header
            if let plateSet, let bar = entry.exercise.bar, showsExtras {
                PlateChip(weightKg: plateSet.weightKg, bar: bar, inventory: inventory) {
                    onTapWeight(plateSet.id)
                }
                    .padding(.top, DGSpace.s3)
            }
            if !entry.lastSessions.isEmpty, showsExtras {
                lastSessionsStrip.padding(.top, DGSpace.s4)
            }
            if let whyTitle = entry.whyTitle, let whyBody = entry.whyBody, showsExtras {
                WhyCard(title: whyTitle, message: whyBody, labelColor: whyLabelColor)
                    .padding(.top, DGSpace.s3)
            }
            rows.padding(.top, DGSpace.s4)
        }
        .dgCard()
    }

    private var header: some View {
        HStack(spacing: DGSpace.s3) {
            ExerciseThumbnail(exercise: entry.exercise)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise.name)
                    .font(DGFont.title2)
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
