import SwiftUI
import UIKit

/// Colour tokens from the design system (deliverable 01). Prefix `--dg-`.
/// Data hues (set types, effort, recovery) are identical in both schemes;
/// only surfaces, ink and text-tints change.
enum DGColor {
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
    static let coral = Color(hex: 0xF4705C)
    static let coralPress = Color(hex: 0xD9503B)
    static let coralWash = Color(hex: 0xF4705C).opacity(0.14)
    static let inkOnCoral = Color(hex: 0x2B0C07)
    /// Coral as small text: steps down in light mode for 4.5:1 contrast.
    static let coralText = dynamic(dark: 0xFF8F7A, light: 0xB83E2A)

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
    static let hitSteps: [Color] = [
        coral.opacity(0.22), coral.opacity(0.46), coral.opacity(0.72), coral
    ]

    // MARK: Helpers
    private static func dynamic(dark: UInt32, light: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: alpha)
                : UIColor(hex: light, alpha: alpha)
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
