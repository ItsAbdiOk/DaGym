import SwiftUI
import Synchronization
import UIKit

/// The five accent themes a user can pick in Settings › Display (plan.md Phase 8). Coral is the
/// shipped brand colour and stays the default; the other four keep the same hue in light and
/// dark mode (only the exact stop shifts) and each has a `text` variant stepped for 4.5:1
/// contrast on small text, matching how `coral`/`coralText` already behave.
enum DGAccent: String, CaseIterable, Codable, Hashable {
    case coral
    case ember
    case lime
    case ice
    case violet

    var displayName: String {
        switch self {
        case .coral: "Coral"
        case .ember: "Ember"
        case .lime: "Lime"
        case .ice: "Ice"
        case .violet: "Violet"
        }
    }

    /// The base accent colour (buttons, active tab, progress fills) for the given scheme.
    /// `coral` is pinned to the single shipped hex in both schemes — that's the value every
    /// existing screen was designed against. The other four step to a deeper, more-saturated
    /// stop in light mode (same reasoning as `surface`/`ink`'s `dynamic` pairs above): a hue
    /// bright enough to read on near-black in dark mode washes out against the light backgrounds.
    func base(dark: Bool) -> Color {
        Color(hex: baseHex(dark: dark))
    }

    /// The raw hex behind `base(dark:)` — for anything that needs the RGB outside SwiftUI (the
    /// Apple Wallet pass's `backgroundColor`).
    func baseHex(dark: Bool) -> UInt32 {
        switch self {
        case .coral:
            // Shipped brand colour — exact hex the app has always used, unchanged either way.
            0xF4705C
        case .ember:
            dark ? 0xF2883C : 0xD9701F
        case .lime:
            dark ? 0x9BD75E : 0x7CBA3E
        case .ice:
            dark ? 0x58C4E8 : 0x2F9CC4
        case .violet:
            // Dark stop reuses the existing `aiViolet` hue so the AI-badge and accent never clash.
            dark ? 0x7B8CFF : 0x5A67D9
        }
    }

    /// Small-text-safe variant: stepped down in light mode for 4.5:1 contrast on `bgBase`/
    /// `surface1`, brightened slightly in dark mode — same treatment as `coralText`.
    func text(dark: Bool) -> Color {
        switch self {
        case .coral:
            Color(hex: dark ? 0xFF8F7A : 0xB83E2A)
        case .ember:
            Color(hex: dark ? 0xFFA666 : 0xA85A16)
        case .lime:
            Color(hex: dark ? 0xB7E888 : 0x4C7A1E)
        case .ice:
            Color(hex: dark ? 0x7ED3F0 : 0x155E77)
        case .violet:
            Color(hex: dark ? 0x9CA8FF : 0x3B49C0)
        }
    }

    /// Pressed/active state (`coralPress`'s role): one fixed darker stop, same in both schemes —
    /// mirrors how the shipped `coralPress` never forked by scheme either.
    var press: Color {
        switch self {
        case .coral: Color(hex: 0xD9503B)
        case .ember: Color(hex: 0xC96B22)
        case .lime: Color(hex: 0x74A83E)
        case .ice: Color(hex: 0x2F92B8)
        case .violet: Color(hex: 0x5566D9)
        }
    }
}

/// Colour tokens from the design system (deliverable 01). Prefix `--dg-`.
/// Data hues (set types, effort, recovery) are identical in both schemes;
/// only surfaces, ink and text-tints change.
enum DGColor {
    /// The active accent theme. `Preferences.init` seeds this from the persisted value at launch
    /// and `accent`'s `didSet` keeps it in sync after that, so every `DGColor.coral`/`coralText`
    /// read below reflects the user's choice without threading `Preferences` through the ~50 call
    /// sites that already read these as bare statics.
    ///
    /// `nonisolated(unsafe)`, not `@MainActor`: `UIColor`'s dynamic-provider closure (used below
    /// to make `coral`/`coralText` re-render on trait changes, same as the plain `dynamic(...)`
    /// tokens above) isn't guaranteed to run on the main actor — asset rendering and widget
    /// snapshotting can resolve traits off-main. `DGAccent` is a plain `String` enum (no payload,
    /// word-sized tag), only ever written from `Preferences` on the main actor, and read far more
    /// often than written, so a torn read is not a practical concern.
    nonisolated(unsafe) static var current: DGAccent = .coral

    // MARK: Surfaces
    static let bgSunken = dynamic(dark: 0x060607, light: 0xE8E6E1)
    static let bgBase = dynamic(dark: 0x0B0B0C, light: 0xF4F3F0)
    static let surface1 = dynamic(dark: 0x16161A, light: 0xFFFFFF)
    static let surface2 = dynamic(dark: 0x202027, light: 0xFAF9F7)
    static let surface3 = dynamic(dark: 0x2A2A33, light: 0xEDEBE6)

    // MARK: Ink
    static let ink1 = dynamic(dark: 0xF6F5F2, light: 0x121213)
    /// 82 % — body copy on glass.
    static let ink2 = dynamic(dark: 0xF6F5F2, light: 0x121213, alpha: 0.82)
    /// 66 % — labels, secondary rows.
    static let ink3 = dynamic(dark: 0xF6F5F2, light: 0x121213, alpha: 0.66)
    /// 46 % — decoration only, never text under 13 pt.
    static let ink4 = dynamic(dark: 0xF6F5F2, light: 0x121213, alpha: 0.46)
    static let hairline = dynamic(dark: 0xFFFFFF, light: 0x121213, alpha: 0.09)

    // MARK: Brand
    // "coral" is the historical name; it now resolves from the active `DGAccent` (`current`,
    // default `.coral`) so every existing call site — buttons, active-tab fills, progress rings —
    // re-themes without being touched. Computed (not `static let`), so each access re-reads
    // `current` rather than caching the value from first launch — but cached *per accent*
    // (`cached(_:)`): a fresh `UIColor` provider per access gave every view body a new, unequal
    // `Color`, so SwiftUI could never skip a subtree that touched coral, and `BodyMapView` was
    // allocating ~60 of them per thumbnail per frame.
    static var coral: Color { cached(.base) { accentAware { $0.base(dark: $1) } } }
    static var coralPress: Color { current.press }
    static var coralWash: Color { cached(.wash) { coral.opacity(0.14) } }
    static let inkOnCoral = Color(hex: 0x2B0C07)
    /// Coral as small text: steps down in light mode for 4.5:1 contrast.
    static var coralText: Color { cached(.text) { accentAware { $0.text(dark: $1) } } }

    // MARK: Set types — each hue is load-bearing
    static let setWarmup = Color(hex: 0xF5B23C)
    static let setAmrap = Color(hex: 0xC58BF0)
    static let setDrop = Color(hex: 0x58C4E8)
    static let setFailure = Color(hex: 0xEE4B3C)
    static let setRestPause = Color(hex: 0x3FCB8E)
    static let setSuperset = Color(hex: 0x7B8CFF)

    // MARK: Effort (RPE / RIR)
    static let rpeEasy = Color(hex: 0x3FCB8E)
    static let rpeModerate = Color(hex: 0x9BD75E)
    static let rpeHard = Color(hex: 0xF2C33F)
    static let rpeVeryHard = Color(hex: 0xF5943A)
    static let rpeMax = Color(hex: 0xEE4B3C)

    // MARK: Recovery ramp — fresh → spent
    static let recovery: [Color] = [
        Color(hex: 0x3FCB8E), Color(hex: 0x9BD75E), Color(hex: 0xF2C33F),
        Color(hex: 0xF5943A), Color(hex: 0xEE4B3C)
    ]

    /// Colour-blind-safe alternative to `recovery`. `recovery`'s green→yellow→red hue sweep is
    /// exactly the axis deuteranopes and protanopes (red/green colour blindness — the two most
    /// common forms) can't separate: the amber/orange/red stops read as one indistinguishable
    /// blob. This ramp instead sweeps blue→yellow while climbing steadily in *lightness* at
    /// every stop — the one property that survives every common form of colour blindness,
    /// deuteranopia/protanopia (red-green) and tritanopia (blue-yellow) alike, because it isn't
    /// carried by hue at all. Same 5-stop "fresh → spent" cardinality as `recovery`, so callers
    /// can index the two ramps identically.
    ///
    /// Stops are matplotlib's "viridis" colormap sampled at 0 / .25 / .5 / .75 / 1 — a palette
    /// purpose-built and validated (Nuñez, Anderton & Renslow, "Optimizing colormaps with
    /// consideration for color vision deficiency...", 2018) to stay monotonic in perceived
    /// lightness under deuteranopia/protanopia/tritanopia simulation:
    ///   0. `#440154` — dark violet (fresh)
    ///   1. `#3B528B` — blue
    ///   2. `#21918C` — teal
    ///   3. `#5EC962` — green
    ///   4. `#FDE725` — yellow (spent)
    /// `HeatmapPaletteTests` checks the monotonic-lightness property directly rather than just
    /// trusting the citation.
    static let recoveryAccessible: [Color] = [
        Color(hex: 0x440154), Color(hex: 0x3B528B), Color(hex: 0x21918C),
        Color(hex: 0x5EC962), Color(hex: 0xFDE725)
    ]

    /// Colour-blind-safe alternative to the consistency calendar's coral ramp (built locally in
    /// `ConsistencyView.HeatmapCard`, not stored here, since its "no activity" stop needs the
    /// dynamic `surface3` rather than a fixed hex). Reuses `recoveryAccessible`'s stops verbatim
    /// — the property that matters, monotonic lightness on a non-red/green axis, is identical
    /// for a "fewer sets → more sets" ramp as it is for "fresh → spent".
    static let consistencyAccessible: [Color] = recoveryAccessible

    /// Picks `recovery` or `recoveryAccessible` for the recovery body map. Either trigger is
    /// enough on its own: the system-wide "Differentiate Without Color" accessibility setting
    /// (`\.accessibilityDifferentiateWithoutColor`), or the user's own in-app
    /// `Preferences.colorBlindHeatmaps` toggle for someone who wants the safer ramp without
    /// flipping the system-wide setting (which also affects other apps).
    static func recoveryRamp(differentiateWithoutColor: Bool, colorBlindHeatmaps: Bool) -> [Color] {
        differentiateWithoutColor || colorBlindHeatmaps ? recoveryAccessible : recovery
    }

    // MARK: Semantic
    static let success = Color(hex: 0x3FCB8E)
    static let warning = Color(hex: 0xF5B23C)
    static let danger = Color(hex: 0xEE4B3C)
    static let info = Color(hex: 0x58C4E8)
    static let prGold = Color(hex: 0xF2C33F)
    static let prGoldLight = Color(hex: 0xF7DC8A)
    static let prGoldDeep = Color(hex: 0xC9932A)
    static let aiViolet = Color(hex: 0x7B8CFF)
    static let aiVioletText = dynamic(dark: 0x7B8CFF, light: 0x3B49C0)
    static let infoText = dynamic(dark: 0x58C4E8, light: 0x155E77)
    static let prGoldText = dynamic(dark: 0xF2C33F, light: 0x6B4C0C)

    /// Body-map fill for a muscle with no data.
    static let bodyMapInert = dynamic(dark: 0xFFFFFF, light: 0x121213, alpha: 0.10)
    /// "Muscles hit" steps: 22 / 46 / 72 / 100 % coral.
    static var hitSteps: [Color] {
        [
            cached(.hit22) { coral.opacity(0.22) }, cached(.hit46) { coral.opacity(0.46) },
            cached(.hit72) { coral.opacity(0.72) }, coral
        ]
    }

    // MARK: Helpers

    /// The accent-derived colours, one `Color` per `(accent, slot)`. Keyed by accent rather than
    /// invalidated when `current` changes, so switching accents hands every call site a
    /// different (unequal) value — which is what makes the views re-render — while within one
    /// accent every read is the same value and SwiftUI's diffing can short-circuit. A `Mutex`,
    /// not `nonisolated(unsafe)`: unlike `current`, a dictionary can't tolerate a torn write.
    private enum AccentSlot: Hashable {
        case base, text, wash, hit22, hit46, hit72
    }

    private static let accentCache = Mutex<[DGAccent: [AccentSlot: Color]]>([:])

    private static func cached(_ slot: AccentSlot, make: () -> Color) -> Color {
        let accent = current
        if let hit = accentCache.withLock({ $0[accent]?[slot] }) { return hit }
        let color = make()
        accentCache.withLock { $0[accent, default: [:]][slot] = color }
        return color
    }
    private static func dynamic(dark: UInt32, light: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: alpha)
                : UIColor(hex: light, alpha: alpha)
        })
    }

    /// Builds a `Color` that re-reads `current` (the active accent) on every trait-collection
    /// resolution, the same way `dynamic(dark:light:)` re-reads its two fixed hexes — so
    /// `coral`/`coralText` track both the user's accent choice and the system's light/dark mode.
    private static func accentAware(_ resolve: @Sendable @escaping (DGAccent, Bool) -> Color) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(resolve(current, trait.userInterfaceStyle == .dark))
        })
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
