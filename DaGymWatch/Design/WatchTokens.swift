import SwiftUI
import WatchKit

/// The 45 mm spec's colour and metric tokens (`docs/design/DaGym Watch - 45mm spec.html`,
/// "Handoff metrics"). Neutral cards on true black, one coral accent; green commits, yellow
/// records, indigo voice — nothing else is tinted. Not the phone's `DGColor`: that file is
/// UIKit-adjacent and the wrist vocabulary is Apple Health's, not DaGym's.
enum WatchColor {
    static let background = Color.black
    static let card = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let cardRaised = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
    static let separator = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)
    static let accent = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x57 / 255)
    static let commit = Color.green
    static let record = Color.yellow
    static let voice = Color.indigo
    static let ink = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
    static let inkSecondary = Color(red: 0x98 / 255, green: 0x98 / 255, blue: 0x9D / 255)
    static let inkTertiary = Color(red: 0x63 / 255, green: 0x63 / 255, blue: 0x66 / 255)
}

/// Sizes in points. `gutter` and the value type step follow the case: 41 mm and the 40 mm SE
/// subtract 2 pt from the gutters (and the RPE row becomes a tap-through), the 49 mm Ultra
/// steps values up 4 pt. Everything else is the same on every watch.
enum WatchMetric {
    /// The 45 mm is 198 pt wide; 44 mm SE 184; 41 mm 176; 40 mm SE 162; 49 mm Ultra 205.
    @MainActor static var screenWidth: CGFloat { WKInterfaceDevice.current().screenBounds.width }
    @MainActor static var isSmall: Bool { screenWidth <= 176 }
    @MainActor static var isLarge: Bool { screenWidth >= 205 }

    @MainActor static var gutter: CGFloat { isSmall ? 10 : 12 }
    static let top: CGFloat = 12
    static let bottom: CGFloat = 14
    /// First and last 24 pt: content there is centred and capped at 150 pt wide. The 40 mm is
    /// 27 pt shorter than the 41 mm, so its bands give up 4 pt each.
    @MainActor static var safeBand: CGFloat { isSmall ? 20 : 24 }
    /// Room for the status-bar clock above a page's title band.
    @MainActor static var pageTop: CGFloat { isSmall ? 20 : 24 }
    static let safeBandMaxWidth: CGFloat = 150

    static let capsule: CGFloat = 50
    static let listRow: CGFloat = 46
    /// 64 pt on the 45 mm; the 44 mm SE is 18 pt shorter and the 40 mm 45 pt shorter, so the
    /// cards give up 4 and 8 pt rather than pushing the capsule off the bottom.
    @MainActor static var stepperCard: CGFloat { isSmall ? 56 : (screenWidth < 198 ? 60 : 64) }
    /// 88 pt on the 45 mm, like the stepper card giving up height on the smaller cases.
    @MainActor static var singleValueCard: CGFloat { isSmall ? 64 : (screenWidth < 198 ? 80 : 88) }
    static let stepperRadius: CGFloat = 16
    static let cardRadius: CGFloat = 14
    static let crownFocusBorder: CGFloat = 2

    /// The value type sizes, stepped up on the Ultra.
    @MainActor static func value(_ base: CGFloat) -> CGFloat { isLarge ? base + 4 : base }
}

/// SF with tabular figures everywhere a number can change width. Nothing under 12 pt.
enum WatchFont {
    static let secondary = Font.system(size: 12, weight: .regular).monospacedDigit()
    static let body = Font.system(size: 13, weight: .regular).monospacedDigit()
    static let bodyMedium = Font.system(size: 15, weight: .medium).monospacedDigit()
    static let title = Font.system(size: 15, weight: .semibold)
    static let button = Font.system(size: 17, weight: .semibold)
    static let unit = Font.system(size: 12, weight: .medium)

    @MainActor static func value(_ base: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: WatchMetric.value(base), weight: weight, design: .rounded).monospacedDigit()
    }
}
