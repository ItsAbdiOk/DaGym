import GymCore

/// Maps the vendored MuscleMap package's 22-base/14-sub-group anatomical regions
/// (`Vendor/MuscleMap/Data/MMMuscle.swift`, `BodySlug`) onto our own 14 `GymCore.Muscle`
/// cases. Many upstream regions feed one of ours; this is the single place that table lives.
///
/// The upstream package draws a broad, illustrative set of regions (including several that
/// aren't one of "our" trainable muscle groups at all — head, hair, hands, feet, knees,
/// ankles, neck). Anything not listed in `slugToMuscle` renders as inert body silhouette
/// rather than an addressable, tintable region.
enum BodyMapMuscleMapping {
    /// Upstream `BodySlug` → our `Muscle`. Many-to-one: several upstream regions can feed one
    /// of ours (`.obliques` and `.serratus`, or the four thigh regions that all feed `.quads`).
    ///
    /// Only slugs that `BodyPathProvider` actually draws appear here. `.rearDeltoid`,
    /// `.upperTrapezius` and `.lowerTrapezius` were listed and have no paths in any of the four
    /// figures (male/female × front/back), so they could never tint anything; they are gone
    /// rather than left as rows that look meaningful and aren't. `.rhomboids` and
    /// `.rotatorCuff` exist in the upstream enum and are likewise undrawn — deliberately absent.
    ///
    /// | Our `Muscle` | Upstream `BodySlug` region(s)                                  |
    /// |---------------|-----------------------------------------------------------------|
    /// | `.traps`      | trapezius                                                       |
    /// | `.delts`      | deltoids, frontDeltoid                                          |
    /// | `.chest`      | chest, upperChest, lowerChest                                   |
    /// | `.abs`        | abs, upperAbs, lowerAbs                                         |
    /// | `.obliques`   | obliques, serratus — upstream models serratus as an obliques sub-group |
    /// |               | and draws it on the ribcage. `scripts/import-exercises.py` maps wger's |
    /// |               | "serratus anterior" to `obliques` to match; the two used to disagree.  |
    /// | `.biceps`     | biceps                                                          |
    /// | `.forearms`   | forearm                                                         |
    /// | `.quads`      | quadriceps, innerQuad, outerQuad, hipFlexors — the hip-flexor region   |
    /// |               | is the upper thigh, where rectus femoris (a quad *and* a hip flexor)   |
    /// |               | sits, so hip-flexor work tinting the quads is the intended reading.    |
    /// | `.calves`     | calves (the shin, `.tibialis`, is left inert — see the table below) |
    /// | `.lats`       | upperBack — upstream has no dedicated "lats"/"latissimus" region; |
    /// |               | `upperBack` is the broad region drawn in that anatomical spot on the back |
    /// | `.triceps`    | triceps                                                         |
    /// | `.lowerBack`  | lowerBack                                                       |
    /// | `.glutes`     | gluteal                                                         |
    /// | `.hams`       | hamstring, adductors (upstream models adductors as a hamstring sub-group, |
    /// |               | not a quad one — followed here rather than overridden)          |
    static let slugToMuscle: [BodySlug: Muscle] = [
        .trapezius: .traps,

        .deltoids: .delts,
        .frontDeltoid: .delts,

        .chest: .chest,
        .upperChest: .chest,
        .lowerChest: .chest,

        .abs: .abs,
        .upperAbs: .abs,
        .lowerAbs: .abs,

        .obliques: .obliques,
        .serratus: .obliques,

        .biceps: .biceps,

        .forearm: .forearms,

        .quadriceps: .quads,
        .innerQuad: .quads,
        .outerQuad: .quads,
        .hipFlexors: .quads,

        .calves: .calves,
        // `.tibialis` is deliberately NOT folded into `.calves`. It is the shin — the front of
        // the lower leg — and tinting it for calf involvement made a kettlebell clean look like
        // it trained the shins. Calves are only visible from behind, so they only light there.

        .upperBack: .lats,

        .triceps: .triceps,

        .lowerBack: .lowerBack,

        .gluteal: .glutes,

        .hamstring: .hams,
        .adductors: .hams
    ]

    /// Regions with no addressable `Muscle` — rendered as inert body silhouette only.
    /// (hair, head, hands, feet, knees, ankles, neck — none are one of our 14 groups.)
    static func muscle(for slug: BodySlug) -> Muscle? { slugToMuscle[slug] }

    /// Muscles drawn on *both* front and back (their region is visible from either
    /// side of the body), matching the old rectangle map's behaviour. Every other
    /// muscle only renders — and only tints/hit-tests — on the side `Muscle.isFront` says.
    static let sharedAcrossSides: Set<Muscle> = [.traps, .delts, .forearms]

    /// Muscles whose region is only visible from behind, overriding `Muscle.isFront`.
    /// `GymCore.Muscle` calls calves a front muscle because it groups the whole lower leg for
    /// programme purposes; anatomically the calf is the back of it, and the front is the shin,
    /// which we leave inert. Drawing calves on the front view lit the shins instead.
    static let backOnly: Set<Muscle> = [.calves]

    /// Whether `muscle`'s region should be addressable (tintable + tappable) when drawing
    /// the given `side`. Matches the previous rectangle-based `BodyMapView`: e.g. `.triceps`
    /// is back-only even though the vendored front paths happen to sketch a sliver of it.
    static func isAddressable(_ muscle: Muscle, on side: BodySide) -> Bool {
        if sharedAcrossSides.contains(muscle) { return true }
        if backOnly.contains(muscle) { return side == .back }
        return muscle.isFront == (side == .front)
    }

    /// Which single side a one-figure thumbnail should draw for an exercise with these primary
    /// movers.
    ///
    /// Six of our fourteen groups (`lats`, `triceps`, `lowerBack`, `glutes`, `hams` and — via
    /// `backOnly` — `calves`) are only addressable from behind. A thumbnail hard-coded to
    /// `.front` therefore drew nothing at all for a Romanian deadlift, and drew a lat pulldown
    /// as two light secondaries with no 100% muscle anywhere. Picking the side from the first
    /// side-specific primary mover guarantees the muscle the exercise is *for* is the one the
    /// reader sees. (Screens with room for two figures use `BodyMapPair` and show both.)
    ///
    /// Muscles in `sharedAcrossSides` are skipped when choosing, since they read the same either
    /// way; an exercise with no primary movers at all, or only shared ones, draws the front.
    static func thumbnailSide(forPrimary muscles: [Muscle]) -> BodySide {
        for muscle in muscles where !sharedAcrossSides.contains(muscle) {
            return isAddressable(muscle, on: .front) ? .front : .back
        }
        return .front
    }
}
