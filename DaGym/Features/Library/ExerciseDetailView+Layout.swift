import GymCore
import SwiftUI
import Synchronization

/// The read-only display pieces of `ExerciseDetailView`'s body — hero art, title, stat tiles and
/// the 1RM row — split out from the main file to stay under the type-body-length cap.
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

    var oneRepMaxRow: some View {
        Button {
            showingCalculator = true
        } label: {
            HStack {
                Image(systemName: "function")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DGColor.prGoldText)
                Text("1RM Calculator")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Image(systemName: "chevron.right").accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: DGTap.min)
            .dgCard(padding: 0)
        }
        .buttonStyle(.dgRow)
    }

    var topRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: DGSpace.s1) {
                    Image(systemName: "chevron.left").accessibilityHidden(true)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Library").dgLabel()
                }
                .foregroundStyle(DGColor.ink3)
            }
            .buttonStyle(.dgControl)
            Spacer()
            Button(action: toggleFavorite) {
                Image(systemName: exercise.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.prGoldText)
                    .frame(width: 36, height: 36)
                    .dgGlass(.regular, in: Circle())
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel(exercise.isFavorite ? "Remove from favourites" : "Add to favourites")
        }
    }

    /// The hero, in order of preference: the illustrated 3-frame vector art where we have it,
    /// otherwise the two-frame photographs, otherwise nothing at all — no placeholder and no
    /// reserved space, so exercises with neither keep today's layout exactly.
    @ViewBuilder
    var heroArt: some View {
        switch ExerciseHeroMedia.choice(for: exercise.seedID) {
        case .vector(let seedID): vectorHero(seedID: seedID)
        case .photo(let seedID): photoHero(seedID: seedID)
        case .none: EmptyView()
        }
    }

    /// The credit line belongs to this branch only: the illustrations are CC BY-SA 4.0 and the
    /// attribution is a licence condition. The photographs are public domain and must never be
    /// captioned as though they carried the same terms.
    private func vectorHero(seedID: String) -> some View {
        VStack(spacing: DGSpace.s2) {
            ExerciseArtView(seedID: seedID, size: 240, animated: true)
                .accessibilityLabel("Illustration demonstrating \(exercise.name)")
            Text("Illustration: Bryl Lim, derived from Everkinetic · CC BY-SA 4.0")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
        .frame(maxWidth: .infinity)
    }

    /// Public-domain photographs (free-exercise-db, Unlicense): no caption, because none is owed
    /// and a credit line here would be read as the licence note above it.
    private func photoHero(seedID: String) -> some View {
        ExercisePhotoView(seedID: seedID, width: 240, animated: true, exerciseName: exercise.name)
            .frame(maxWidth: .infinity)
    }

    var titleBlock: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            HStack(alignment: .top) {
                Text(exercise.name)
                    .font(DGFont.title1)
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(2)
                Spacer()
                BodyMapPair(intensity: exercise.hitMap, height: 56)
            }
            Text(equipmentLine)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
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

    var statTiles: some View {
        DGAdaptiveStack(spacing: DGSpace.s3, threshold: .accessibility3) {
            goldStat
            StatTile(value: exercise.bestSet ?? "—", label: "Best Set")
                .dgCard(radius: 14, padding: 0)
            StatTile(value: "\(exercise.sessions)", label: "Sessions")
                .dgCard(radius: 14, padding: 0)
        }
    }

    var goldStat: some View {
        StatTile(
            value: exercise.bestE1RM.map { preferences.formatWeight(kg: $0) } ?? "—",
            label: "Best E1RM", tint: DGColor.prGoldText
        )
        .dgCard(
            radius: 14, fill: DGColor.prGold.opacity(0.10), stroke: DGColor.prGold.opacity(0.35), padding: 0
        )
    }
}

/// Which visual an exercise's hero shows. Split out from the `@ViewBuilder` so the precedence
/// rule — illustrated vector art beats photographs, and neither means *no* hero and no reserved
/// space — is one value a test can assert on rather than a branch buried in a view body.
enum ExerciseHeroMedia: Equatable {
    /// We have hand-drawn 3-frame art: CC BY-SA 4.0, and credited on screen.
    case vector(String)
    /// No art, but two public-domain photographs: no credit line.
    case photo(String)
    /// Nothing to show. The hero renders nothing at all and takes up no height.
    case none

    static func choice(for seedID: String?) -> ExerciseHeroMedia {
        guard let seedID else { return .none }
        if ExerciseArtCatalog.frames(for: seedID) != nil { return .vector(seedID) }
        if ExercisePhotoCatalog.hasPhotos(for: seedID) { return .photo(seedID) }
        return .none
    }
}
