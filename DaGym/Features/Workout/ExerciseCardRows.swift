import GymCore
import SwiftUI

// `ExerciseCard`'s two one-line layouts and the art thumbnail they share with the on-deck
// card (`OnDeckExerciseCard.swift`). Both rows are the prototype's collapsed row: a 34 pt
// thumbnail, the name over "3 × 10 · 30 kg", and "0/3" at the right.

/// Collapsed one-line row for an incomplete exercise that isn't on deck yet.
struct CollapsedExerciseRow: View {
    var entry: WorkoutExerciseEntry
    var onStartTimed: (UUID) -> Void

    @Environment(Preferences.self) private var preferences

    private var firstOpenSetID: UUID? { entry.nextOpenSetID ?? entry.sets.first?.id }

    var body: some View {
        ExerciseRowFrame(entry: entry, summary: summaryLine) {
            if entry.isTimed {
                Button {
                    if let setID = firstOpenSetID { onStartTimed(setID) }
                } label: {
                    Text("Start")
                        .font(DGFont.condensedLabel(12))
                        .foregroundStyle(DGColor.ink1)
                        .padding(.horizontal, DGSpace.s3)
                        .frame(minHeight: 32)
                        .dgInkPill(radius: DGRadius.pill, opacity: 0.07)
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel("Start \(entry.exercise.name)")
            } else {
                ExerciseProgressLabel(entry: entry)
            }
        }
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

/// One-liner for a finished exercise: the same row, "4/4" at the right.
struct CompletedExerciseRow: View {
    var entry: WorkoutExerciseEntry

    @Environment(Preferences.self) private var preferences

    var body: some View {
        ExerciseRowFrame(entry: entry, summary: summary) {
            ExerciseProgressLabel(entry: entry)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        guard let first = entry.sets.first else { return "Done" }
        if entry.isCardio {
            let meters = entry.distanceMeters
            let seconds = entry.sets.compactMap(\.durationSeconds).reduce(0, +)
            return SetEntry(weightKg: 0, reps: 0, durationSeconds: seconds, distanceMeters: meters)
                .cardioSummary(unit: preferences.distanceUnit)
        }
        if entry.isTimed {
            let best = entry.sets.compactMap(\.durationSeconds).max() ?? 0
            return "\(entry.sets.count) holds · best \(WorkoutSession.clock(best))"
        }
        guard first.weightKg > 0 else { return "\(entry.sets.count) × \(first.reps)" }
        let weight = preferences.formatWeight(kg: first.weightKg)
        return "\(entry.sets.count) × \(first.reps) · \(weight) \(preferences.unitSymbol)"
    }
}

/// The collapsed row's chrome: thumbnail, name, summary, and whatever sits at the trailing
/// edge (the done count, or "Start" for a hold).
private struct ExerciseRowFrame<Trailing: View>: View {
    var entry: WorkoutExerciseEntry
    var summary: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            ExerciseThumbnail(exercise: entry.exercise, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.exercise.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(1)
                Text(summary)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
            }
            Spacer(minLength: DGSpace.s2)
            trailing()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .dgTile(radius: 18, opacity: 0.52)
    }
}

/// "0/3" — done count over planned count, accent once every set is ticked.
private struct ExerciseProgressLabel: View {
    var entry: WorkoutExerciseEntry

    var body: some View {
        Text("\(entry.doneCount)/\(entry.sets.count)")
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(entry.isComplete ? DGColor.coralText : DGColor.ink3)
            .accessibilityLabel("\(entry.doneCount) of \(entry.sets.count) sets done")
    }
}

/// The exercise's picture in the row and card corners: the illustrated art where we have it,
/// the generated line-art next, the photo after that, and the body-map thumbnail for
/// everything else — so the slot is never an
/// empty dashed box. `ExerciseHeroMedia.choice(for:)` already follows media aliases, so a
/// same-movement exercise borrows its twin's picture here too.
struct ExerciseThumbnail: View {
    var exercise: ExerciseInfo
    var size: CGFloat = 44

    var body: some View {
        Group {
            switch ExerciseHeroMedia.choice(for: exercise.seedID) {
            case .vector(let seedID):
                ExerciseArtView(seedID: seedID, size: size - 8)
            case .frames(let seedID):
                // The downsampled middle frame on paper, through the same ImageIO path.
                PhotoThumbnail(seedID: seedID, size: size, kind: .frames)
                    .background(Color.white)
            case .photo(let seedID):
                // The downsampled start frame, not `ExercisePhotoView`: that decodes the full
                // 1.7 MB pair and runs a crossfade per row, which put the Library at ~490 MB.
                PhotoThumbnail(seedID: seedID, size: size, kind: .photo)
            case .none:
                BodyMapView(
                    side: BodyMapMuscleMapping.thumbnailSide(forPrimary: exercise.primary),
                    mode: .hit,
                    intensity: exercise.hitMap
                )
                .padding(6)
            }
        }
        .frame(width: size, height: size)
        .background(DGColor.surface3, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        // Decorative: the exercise name beside it is the content.
        .accessibilityHidden(true)
    }
}

/// A 44 pt square from the exercise photo (start frame) or the generated line-art (middle
/// frame), decoded straight to thumbnail size through `MachineThumbnailStore`'s ImageIO path
/// and cached there.
private struct PhotoThumbnail: View {
    enum Kind { case photo, frames }

    var seedID: String
    var size: CGFloat
    var kind: Kind
    @State private var image: Image?

    var body: some View {
        ZStack {
            if let image {
                image.resizable().scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .task(id: seedID) { image = await load() }
    }

    private func load() async -> Image? {
        switch kind {
        case .photo: await MachineThumbnailStore.shared.thumbnail(forSeedID: seedID)
        case .frames: await MachineThumbnailStore.shared.frameThumbnail(forSeedID: seedID)
        }
    }
}
