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
    /// Upstream `BodySlug` → our `Muscle`. Many-to-one: e.g. `.upperTrapezius` and
    /// `.lowerTrapezius` (drawn only as always-visible sub-groups upstream, unused by our
    /// data files, kept here for completeness) both feed `.traps`, same as the parent
    /// `.trapezius` region itself.
    ///
    /// | Our `Muscle` | Upstream `BodySlug` region(s)                                  |
    /// |---------------|-----------------------------------------------------------------|
    /// | `.traps`      | trapezius, upperTrapezius, lowerTrapezius                       |
    /// | `.delts`      | deltoids, frontDeltoid, rearDeltoid                             |
    /// | `.chest`      | chest, upperChest, lowerChest                                   |
    /// | `.abs`        | abs, upperAbs, lowerAbs                                         |
    /// | `.obliques`   | obliques, serratus (upstream models serratus as an obliques sub-group) |
    /// | `.biceps`     | biceps                                                          |
    /// | `.forearms`   | forearm                                                         |
    /// | `.quads`      | quadriceps, innerQuad, outerQuad, hipFlexors                    |
    /// | `.calves`     | calves, tibialis (no separate shin region in our 14, folded into calves) |
    /// | `.lats`       | upperBack — upstream has no dedicated "lats"/"latissimus" region; |
    /// |               | `upperBack` is the broad region drawn in that anatomical spot on the back |
    /// | `.triceps`    | triceps                                                         |
    /// | `.lowerBack`  | lowerBack                                                       |
    /// | `.glutes`     | gluteal                                                         |
    /// | `.hams`       | hamstring, adductors (upstream models adductors as a hamstring sub-group, |
    /// |               | not a quad one — followed here rather than overridden)          |
    static let slugToMuscle: [BodySlug: Muscle] = [
        .trapezius: .traps,
        .upperTrapezius: .traps,
        .lowerTrapezius: .traps,

        .deltoids: .delts,
        .frontDeltoid: .delts,
        .rearDeltoid: .delts,

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
        .tibialis: .calves,

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
    static let sharedAcrossSides: Set<Muscle> = [.traps, .delts, .forearms, .calves]

    /// Whether `muscle`'s region should be addressable (tintable + tappable) when drawing
    /// the given `side`. Matches the previous rectangle-based `BodyMapView`: e.g. `.triceps`
    /// is back-only even though the vendored front paths happen to sketch a sliver of it.
    static func isAddressable(_ muscle: Muscle, on side: BodyMapView.Side) -> Bool {
        if sharedAcrossSides.contains(muscle) { return true }
        return muscle.isFront == (side == .front)
    }
}
