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
