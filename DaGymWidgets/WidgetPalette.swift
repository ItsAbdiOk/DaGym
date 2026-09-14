import SwiftUI
import UIKit

/// Hardcoded copies of the six `DGColor` hexes this widget needs. The widget extension can't
/// import `DGColor` (it's app-target-only and leans on UIKit trait callbacks that don't fire
/// the same way here), so these are pinned to the design system's values by hand — keep them in
/// sync with `DaGym/Design/DGColor.swift` if those six ever change.
enum WidgetPalette {
    static let background = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255)
    static let ink = Color(red: 0xF6 / 255, green: 0xF5 / 255, blue: 0xF2 / 255)
    static let inkMuted = ink.opacity(0.66)
    static let coral = Color(red: 0xF4 / 255, green: 0x70 / 255, blue: 0x5C / 255)
    static let green = Color(red: 0x3F / 255, green: 0xCB / 255, blue: 0x8E / 255)
    static let inkOnCoral = Color(red: 0x2B / 255, green: 0x0C / 255, blue: 0x07 / 255)

    /// Hardcoded copies of `RoutineTint`'s six colors, for `RoutineWidgetGlyph` — the widget
    /// extension can't import `DGColor`/`RoutineTint` (app-target-only), so these are pinned by
    /// hand from `DaGym/Design/DGColor.swift`'s fixed hexes. Falls back to `coral` for a raw
    /// value this widget build doesn't know, same as `RoutineTint.named` does in the app.
    static func routineTint(_ raw: String?) -> Color {
        switch raw {
        case "gold": Color(red: 0xF2 / 255, green: 0xC3 / 255, blue: 0x3F / 255)
        case "violet": Color(red: 0x7B / 255, green: 0x8C / 255, blue: 0xFF / 255)
        case "ice": Color(red: 0x58 / 255, green: 0xC4 / 255, blue: 0xE8 / 255)
        case "green": green
        case "red": Color(red: 0xEE / 255, green: 0x4B / 255, blue: 0x3C / 255)
        default: coral
        }
    }
}

/// A routine's glyph in a tinted rounded square — the widget/Live Activity mirror of the app
/// target's `RoutineGlyph`, which this extension can't compile against (it leans on `DGColor`).
/// Keep the two drawings in sync by eye if either changes.
struct RoutineWidgetGlyph: View {
    var symbolName: String
    var tint: String?
    var size: CGFloat = 28

    var body: some View {
        let color = WidgetPalette.routineTint(tint)
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
