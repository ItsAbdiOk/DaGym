import GymCore
import SwiftUI

// `ExerciseCard`'s two one-line layouts and the body-map thumbnail they share with the on-deck
// card (`OnDeckExerciseCard.swift`).

/// Collapsed one-line row for an incomplete exercise that isn't on deck yet.
struct CollapsedExerciseRow: View {
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
struct CompletedExerciseRow: View {
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

struct ExerciseThumbnail: View {
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
