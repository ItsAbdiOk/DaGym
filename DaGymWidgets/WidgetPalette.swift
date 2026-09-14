import SwiftUI
import UIKit

/// The widget/Live Activity mirror of `DGColor`. The widget extension can't import `DGColor`
/// (it's app-target-only and leans on UIKit trait callbacks that don't fire the same way here),
/// so these are pinned to the design system's values by hand — keep them in sync with
/// `DaGym/Design/DGColor.swift` if any of them change.
///
/// Unlike the old version, this is *resolved*, not hard-coded: the accent and the light/dark
/// choice come from the user's own `Preferences`, carried through `WidgetSnapshot` (widgets) and
/// `RestActivityAttributes` (Live Activity). A lifter on the Ice accent in Light mode used to get
/// a coral-on-near-black widget regardless.
struct WidgetPalette {
    var background: Color
    var ink: Color
    var accent: Color
    var green: Color
    var inkOnAccent: Color

    var inkMuted: Color { ink.opacity(0.66) }

    /// `DGColor`'s shipped dark palette — used when nothing has been written yet.
    static let fallback = WidgetPalette(accent: "coral", appearance: "system", systemIsDark: true)

    /// - Parameters:
    ///   - accent: a `DGAccent` raw value.
    ///   - appearance: a `Preferences.Appearance` raw value; "system" defers to `systemIsDark`.
    ///   - systemIsDark: the viewer's current `colorScheme`.
    init(accent: String, appearance: String, systemIsDark: Bool) {
        let isDark: Bool
        switch appearance {
        case "light": isDark = false
        case "dark": isDark = true
        default: isDark = systemIsDark
        }
        background = isDark
            ? Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255)
            : Color(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xF0 / 255)
        ink = isDark
            ? Color(red: 0xF6 / 255, green: 0xF5 / 255, blue: 0xF2 / 255)
            : Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x13 / 255)
        self.accent = Self.accentColor(accent, dark: isDark)
        green = isDark
            ? Color(red: 0x3F / 255, green: 0xCB / 255, blue: 0x8E / 255)
            : Color(red: 0x2E / 255, green: 0xA2 / 255, blue: 0x6E / 255)
        inkOnAccent = Color(red: 0x2B / 255, green: 0x0C / 255, blue: 0x07 / 255)
    }

    private init(background: Color, ink: Color, accent: Color, green: Color, inkOnAccent: Color) {
        self.background = background
        self.ink = ink
        self.accent = accent
        self.green = green
        self.inkOnAccent = inkOnAccent
    }

    /// `DGAccent.base(dark:)`, transcribed. Unknown raw values fall back to the brand coral, the
    /// same way `DGAccent(rawValue:) ?? .coral` does in the app.
    private static func accentColor(_ raw: String, dark: Bool) -> Color {
        switch raw {
        case "ember": Color(hex: dark ? 0xF2883C : 0xD9701F)
        case "lime": Color(hex: dark ? 0x9BD75E : 0x7CBA3E)
        case "ice": Color(hex: dark ? 0x58C4E8 : 0x2F9CC4)
        case "violet": Color(hex: dark ? 0x7B8CFF : 0x5A67D9)
        default: Color(hex: 0xF4705C)
        }
    }

    /// Hard-coded copies of `RoutineTint`'s six colors, for `RoutineWidgetGlyph`. A routine's tint
    /// is the routine's own identity, not the app theme, so these stay fixed — but an unknown raw
    /// value falls back to the *user's* accent rather than to coral.
    func routineTint(_ raw: String?) -> Color {
        switch raw {
        case "gold": Color(red: 0xF2 / 255, green: 0xC3 / 255, blue: 0x3F / 255)
        case "violet": Color(red: 0x7B / 255, green: 0x8C / 255, blue: 0xFF / 255)
        case "ice": Color(red: 0x58 / 255, green: 0xC4 / 255, blue: 0xE8 / 255)
        case "green": green
        case "red": Color(red: 0xEE / 255, green: 0x4B / 255, blue: 0x3C / 255)
        default: accent
        }
    }
}

extension Color {
    /// `DGColor`'s `Color(hex:)`, duplicated here because that file is app-target-only.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct WidgetPaletteKey: EnvironmentKey {
    static let defaultValue = WidgetPalette.fallback
}

extension EnvironmentValues {
    /// Set once at each widget/Live Activity root; every view below reads the resolved theme
    /// instead of reaching for a global.
    var widgetPalette: WidgetPalette {
        get { self[WidgetPaletteKey.self] }
        set { self[WidgetPaletteKey.self] = newValue }
    }
}

/// A routine's glyph in a tinted rounded square — the widget/Live Activity mirror of the app
/// target's `RoutineGlyph`, which this extension can't compile against (it leans on `DGColor`).
/// Keep the two drawings in sync by eye if either changes.
struct RoutineWidgetGlyph: View {
    var symbolName: String
    var tint: String?
    var size: CGFloat = 28

    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let color = palette.routineTint(tint)
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                color.opacity(0.22), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Barlow Condensed for widget numbers, falling back to the system rounded font if the bundled
/// TTF failed to register (widgets need their own `UIAppFonts` entry — see `project.yml` — since
/// they don't share the app's Info.plist).
enum WidgetFont {
    static func condensed(size: CGFloat) -> Font {
        UIFont(name: "BarlowCondensed-Bold", size: size) != nil
            ? .custom("BarlowCondensed-Bold", size: size)
            : .system(.title, design: .rounded).bold()
    }
}
