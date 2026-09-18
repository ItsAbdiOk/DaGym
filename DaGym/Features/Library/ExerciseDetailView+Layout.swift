import GymCore
import SwiftUI
import Synchronization

/// The read-only display pieces of `ExerciseDetailView`'s body — the illustration card and the
/// stat tiles — split out from the main file to stay under the type-body-length cap.
extension ExerciseDetailView {
    /// The seed keeps instructions as one string with the numbering inline; the parser lives in
    /// GymCore so the splitting rules are testable without a view. Parsed once per exercise:
    /// `body` reads this on every re-render (favourite toggle, sheet dismiss) and the parse walks
    /// an ~8 KB string, so a cache keyed on the raw text keeps it off the render path.
    var instructionSteps: [ExerciseInstructionStep] {
        Self.instructionCache.withLock { cache in
            if let hit = cache[exercise.instructions] { return hit }
            let steps = ExerciseInstructions.steps(from: exercise.instructions)
            if cache.count > 32 { cache.removeAll(keepingCapacity: true) }
            cache[exercise.instructions] = steps
            return steps
        }
    }

    private static let instructionCache = Mutex<[String: [ExerciseInstructionStep]]>([:])

    /// The illustration card (the prototype's 150 pt slot): the illustrated 3-frame vector art
    /// where we have it, otherwise the two-frame photographs, otherwise the body-map pair lit
    /// on the muscles worked — so every exercise gets a picture and the layout never jumps.
    var heroCard: some View {
        VStack(spacing: DGSpace.s3) {
            heroMedia
            // The muscles line is a door to the map, where the same muscles are scored.
            NavigationLink(value: ScreenDestination.muscleMap(.balance)) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(muscleAndEquipmentLine)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .multilineTextAlignment(.center)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DGColor.ink4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.dgRow)
            .accessibilityHint("Opens the muscle map")
            .accessibilityIdentifier(A11yID.exerciseMuscles)
        }
        .frame(maxWidth: .infinity)
        .dgCard(radius: 20, padding: DGSpace.s4)
    }

    @ViewBuilder
    private var heroMedia: some View {
        switch ExerciseHeroMedia.choice(for: exercise.seedID) {
        case .vector(let seedID): vectorHero(seedID: seedID)
        case .photo(let seedID): photoHero(seedID: seedID)
        case .none:
            BodyMapPair(intensity: exercise.hitMap, height: 140)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Muscles worked by \(exercise.name)")
        }
    }

    /// The credit line belongs to this branch only: the illustrations are CC BY-SA 4.0 and the
    /// attribution is a licence condition. The photographs are public domain and must never be
    /// captioned as though they carried the same terms.
    private func vectorHero(seedID: String) -> some View {
        VStack(spacing: DGSpace.s2) {
            ExerciseArtView(seedID: seedID, size: 160, animated: true)
                .accessibilityLabel("Illustration demonstrating \(exercise.name)")
            Text("Illustration: Bryl Lim, derived from Everkinetic · CC BY-SA 4.0")
                .font(Font.system(.caption2))
                .foregroundStyle(DGColor.ink4)
        }
        .frame(maxWidth: .infinity)
    }

    /// Photographs. The free-exercise-db pairs are public domain and get no caption, because
    /// none is owed and a credit line would be read as the licence note above it; the CC BY /
    /// CC BY-SA images from wger and Wikimedia Commons carry the line their licence asks for.
    /// `seedID` is already alias-resolved, so the credit follows the picture that is shown.
    private func photoHero(seedID: String) -> some View {
        VStack(spacing: DGSpace.s2) {
            ExercisePhotoView(seedID: seedID, width: 240, animated: true, exerciseName: exercise.name)
            if let caption = ExercisePhotoCredits.credit(for: seedID)?.captionLine {
                Text(caption)
                    .font(Font.system(.caption2))
                    .foregroundStyle(DGColor.ink4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Chest · triceps · barbell · olympic bar · 2.5 kg increment" — the old title block's
    /// subtitle, now the caption under the picture since the name moved to the nav bar.
    var muscleAndEquipmentLine: String {
        "\(exercise.muscleLine) · \(equipmentLine)"
    }

    /// "barbell · olympic bar · 2.5 kg increment"; a bodyweight move has no bar and no
    /// increment worth stating, so it reads just "bodyweight".
    var equipmentLine: String {
        var parts = [exercise.equipment]
        if let bar = exercise.bar { parts.append(bar.name.lowercased()) }
        if exercise.incrementKg > 0 {
            let increment = preferences.formatWeight(kg: exercise.incrementKg)
            parts.append("\(increment) \(preferences.unitSymbol) increment")
        }
        return parts.joined(separator: " · ")
    }

    /// Three white tiles: best e1RM · best set · sessions — each a door to where the number
    /// comes from (the chart on that metric, or the recent-sessions card).
    func statTiles(onJump: @escaping (StatDoor) -> Void) -> some View {
        DGAdaptiveStack(spacing: DGSpace.s2, threshold: .accessibility3) {
            Button { onJump(.e1rm) } label: {
                DetailStatTile(value: bestE1RMLabel, label: "Best e1RM")
            }
            .buttonStyle(.dgCard)
            .accessibilityHint("Shows the 1RM chart")
            Button { onJump(.topSet) } label: {
                DetailStatTile(value: exercise.bestSet ?? "—", label: "Best set")
            }
            .buttonStyle(.dgCard)
            .accessibilityHint("Shows the top-set chart")
            Button { onJump(.sessions) } label: {
                DetailStatTile(value: "\(exercise.sessions)", label: "Sessions")
            }
            .buttonStyle(.dgCard)
            .accessibilityHint("Shows recent sessions")
        }
    }
}

/// One of the detail screen's stat tiles: an 18 pt bold tabular figure over an 11 pt label.
struct DetailStatTile: View {
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(Font.system(.headline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Font.system(.caption2, weight: .medium))
                .foregroundStyle(DGColor.ink3)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, DGSpace.s3)
        .dgCard(radius: 16, padding: 0)
        .accessibilityElement(children: .combine)
    }
}

/// Which visual an exercise's hero shows. Split out from the `@ViewBuilder` so the precedence
/// rule — illustrated vector art beats photographs, and neither means the body map stands in —
/// is one value a test can assert on rather than a branch buried in a view body.
///
/// The associated seedID is the one whose media to load: for an aliased exercise
/// (`ExerciseMediaAliases`) that is the alias target, so the same-movement exercise's art or
/// photographs — and their credit line — are what appears.
enum ExerciseHeroMedia: Equatable {
    /// We have hand-drawn 3-frame art: CC BY-SA 4.0, and credited on screen.
    case vector(String)
    /// No art, but photographs: public domain (no credit line) or CC-licensed (credited).
    case photo(String)
    /// Neither: the hero falls back to the body-map pair.
    case none

    static func choice(for seedID: String?) -> ExerciseHeroMedia {
        guard let seedID else { return .none }
        let resolved = ExerciseMediaAliases.resolve(seedID)
        if ExerciseArtCatalog.frames(for: resolved) != nil { return .vector(resolved) }
        if ExercisePhotoCatalog.hasPhotos(for: resolved) { return .photo(resolved) }
        return .none
    }
}
